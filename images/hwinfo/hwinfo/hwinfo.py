from hwinfo.sed import Sed
import os
import json
import subprocess
import logging
from hwinfo.run_cmd import run_cmd

def get_cpus():
    try:
        r = run_cmd("lscpu --json")
        d = json.loads(r)
        ret = dict()
        for prop in d.get('lscpu'):
            ret.update({prop['field'].strip(':').strip('(s)'): prop['data']})
        return ret
    except Exception as e:
        logging.error(f"failed to run `lscpu --json` command {str(e)}")
        return {'error': e.args}


def get_nvdimm():
    try:
        r = run_cmd('ndctl list -vv')
        logging.info(f"ndctl returned: {r}")
        if len(r) == 0:
            return []
        return json.loads(r)
    except Exception as e:
        logging.error(f"failed to run `ndctl list -vv` command {str(e)}")
        return []

def get_fio(dest_file="/tmp/fio_test"):
    try:
        cmd = f'fio --name=randwrite --ioengine=libaio --iodepth=1 --rw=randwrite --bs=4k --direct=1 --numjobs=1 --size=10m --time_base=1 --runtime=10 --group_reporting --filename={dest_file} --output-format=json'
        r = run_cmd(cmd)
        return json.loads(r)
    except Exception as e:
        logging.error(f"failed to run `{cmd}` command {str(e)}")
        {'error': e.args, 'command': cmd}


def get_nvme_list(selftest_url=None):
    """
    "mdev -s" scans /sys/class/xxx, looking for directories which have dev
     file (it is of the form "M:m\n"). Example: /sys/class/tty/tty0/dev
     contains "4:0\n". Directory name is taken as device name, path component
     directly after /sys/class/ as subsystem. In this example, "tty0" and "tty".
     Then mdev creates the /dev/device_name node.
     If /sys/class/.../dev file does not exist, mdev still may act
     on this device: see "@|$|*command args..." parameter in config file.
    """
    try:
        run_cmd("mdev -s")
        r = run_cmd("nvme list -o json")
        nvme_list = json.loads(r)
        sed_obj = Sed(nvme_list, selftest_url)
        if not sed_obj.seds:
            return nvme_list
        sed_obj.reset_seds()
        for nvme in nvme_list["Devices"]:
            isn = nvme["SerialNumber"]
            sed = sed_obj.get_sed(isn)
            if not sed:
                continue
            nvme["is_sed"] = True
            err = sed.get("error")
            if err:
                nvme["error"] = err
        return nvme_list
    except Exception as e:
        return {'error': e.args}


def get_ssd_per_numa():
    try:
        if len(os.listdir('/sys/class/nvme')) == 0:
            logging.info("directory /sys/class/nvme is empty - no nvme devices found")
            return {}
        ssd_raw = run_cmd("cat /sys/class/nvme/nvme*/device/numa_node")

        ssd_per_numa = {'numa0': list(ssd_raw).count('0') + list(ssd_raw).count('3'), 'numa1': list(ssd_raw).count('1') + list(ssd_raw).count('2')}

        return ssd_per_numa
    except Exception as e:
        logging.error(f"failed to run `cat /sys/class/nvme/nvme*/device/numa_node` command {str(e)}")
        return {}


def get_loaded_nvme_devices():
    try:
        if len(os.listdir('/sys/class/nvme')) == 0:
            logging.info("directory /sys/class/nvme is empty - no nvme devices found")
            return []

        r = run_cmd("ls /dev | grep nvme")
        return r.split("\n")[:-1]
    except Exception as e:
        logging.error(f"failed to run `ls /dev | grep nvme` command {str(e)}")
        return []


def get_lspci_lf():
    '''
    lspci indicate if exist and if lightfield is overpassed
    '''
    try:
        r = run_cmd('lspci|grep -iE "8764|1d9a"')
        lines = r.strip().split('\n')
        lf_pci_lst = {}
        for line in lines:
            port, val = line.split(".", 1)
            lf_pci_lst[str(port).strip()] = val[2:]
        return lf_pci_lst
    except subprocess.CalledProcessError as e:
        if e.returncode == 1:  # found no device
            return {}
        return {'errcode': e.returncode, 'error': e.args}
    except Exception as e:
        return {'error': e.args}


def get_lshw():
    try:
        r = run_cmd("lshw -json")
        return json.loads(r)
    except Exception as e:
        logging.error(f"failed to run `lshw -json` command {str(e)}")
        return {}


def numa_mem():
    '''
    output for reference:
    available: 2 nodes (0-1)
    node 0 cpus: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 28 29 30 31 32 33 34 35 36 37 38 39 40 41
    node 0 size: 96521 MB
    node 0 free: 19207 MB
    node 1 cpus: 14 15 16 17 18 19 20 21 22 23 24 25 26 27 42 43 44 45 46 47 48 49 50 51 52 53 54 55
    node 1 size: 96740 MB
    node 1 free: 95273 MB
    node distances:
    node   0   1
      0:  10  21
      1:  21  10
    '''
    try:
        def parse_numactl(output):
            ret = dict()
            output = output.split('\n')
            for line in output:
                if 'cpus' in line:
                    if 'node 0' in line:
                        if 'numa0' not in ret:
                            ret['numa0'] = {}
                        line = line.split(':')[1]
                        ret['numa0']['cpu_num'] = len(line.split())
                    if 'node 1' in line:
                        if 'numa1' not in ret:
                            ret['numa1'] = {}
                        line = line.split(':')[1]
                        ret['numa1']['cpu_num'] = len(line.split())
                if 'size' in line:
                    if 'node 0' in line:
                        if 'numa0' not in ret:
                            ret['numa0'] = {}
                        ret['numa0']['mem_size'] = line.split(':', 1)[-1].strip()
                    if 'node 1' in line:
                        if 'numa1' not in ret:
                            ret['numa1'] = {}
                        ret['numa1']['mem_size'] = line.split(':', 1)[-1].strip()
            return ret

        r = run_cmd("numactl -H")
        return parse_numactl(r)
    except Exception as e:
        logging.error(f"failed to run numactl -H command {str(e)}")
        return {}

def lightfield():
    return {
        "lspci": {},
        "numa0": {
            "errcode": 1,
            "error": "found no device"
        },
        "numa1": {
            "errcode": 1,
            "error": "found no device"
        },
        "programtool": {
            "numa0": {},
            "numa1": {}
        }
    }

class HWinfo:
    def __init__(self):
        self.data = None

    def run(self, selftest_url=None):
        # // Create the /mountAction mountpoint (no folders exist previously in scratch container)
        # err := os.Mkdir(mountAction, os.ModeDir)
        # if err != nil {
        #     log.Fatalf("Error creating the action Mountpoint [%s]", mountAction)
        # }

        # // Mount the block device to the /mountAction point
        # err = syscall.Mount(blockDevice, mountAction, filesystemType, 0, "")
        # if err != nil {
        #     log.Fatalf("Mounting [%s] -> [%s] error [%v]", blockDevice, mountAction, err)
        # }
        # log.Infof("Mounted [%s] -> [%s]", blockDevice, mountAction)

        BLOCK_DEVICE = os.getenv("BLOCK_DEVICE", "/dev/sda")

        # BLOCK_DEVICE = os.getenv("BLOCK_DEVICE", "/dev/sda2")
        # mountAction = "/mountAction"
        # # python mount directory
        # logging.info(f"mkdir {mountAction}")
        # os.system(f"mkdir -p {mountAction}")
        # logging.info(f"mounting {BLOCK_DEVICE} to {mountAction}")
        # os.system(f"mount {BLOCK_DEVICE} {mountAction}")

        lsblk_output = run_cmd(f"lsblk")
        logging.info(f"lsblk_output: {lsblk_output}")

        self.data = {
            "cpu": get_cpus(),
            "nvme_list": get_nvme_list(selftest_url),
            "fio": get_fio(dest_file=f"{BLOCK_DEVICE}"),
            #"fio": get_fio(dest_file=f"{mountAction}/fio_test"),
            # "fio": None,
            "lshw": get_lshw(),
            "ssd_per_numa": get_ssd_per_numa(),
            "nvdimm": get_nvdimm(),
            "loaded_nvme_dev": get_loaded_nvme_devices(),
            "numactl": numa_mem(),
            "lightfield": lightfield()
        }
        self.data["cpu"]["Architecture"] = "x86_64"

        #os.system(f"umount {mountAction}")
        return self.data
