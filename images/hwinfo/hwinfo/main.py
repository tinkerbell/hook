#!/usr/bin/env python3
import json
import os
import logging
import requests
import time
import urllib3.exceptions
from hwinfo import hwinfo

cmdline_path = "/proc/cmdline"

def basic_logging_config():
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s',
        handlers=[
            logging.FileHandler("/var/log/hwinfo_verbose.log"),
            logging.StreamHandler()
        ]
    )

class Config(dict):
    def __init__(self) -> None:
        self["self_test_base_url"] = None
        self["mac"] = None
        self["ip"] = None
        self["id"] = None

    def verify(self):
        if not self["self_test_base_url"]:
            raise ValueError("self_test_base_url is not set")
        if not self["mac"]:
            raise ValueError("mac is not set")
        if not self["id"]:
            raise ValueError("id is not set")
        if not self["ip"]:
            #raise ValueError("ip is not set")
            self["ip"] = "no-ip"
            logging.warn("didn't get IP from config - this field is not mandatory")


def read_config_env_vars() -> Config:
    config = Config()
    config["self_test_base_url"] = os.getenv("SELF_TEST_BASE_URL", None)
    config["mac"] = os.getenv("MAC", None)
    config["ip"] = os.getenv("IP", None)
    config["id"] = os.getenv("ID", None)
    logging.info(f"read_config_env_vars: {config}")
    return config


def read_config_from_cmdline() -> Config:
    config = Config()
    with open(cmdline_path, "r") as f:
        cmdline = f.read()
    logging.info(f"/proc/cmdline content: {cmdline}")

    for arg in cmdline.split():
        if arg.lower().startswith("SELF_TEST_BASE_URL=".lower()):
            config["self_test_base_url"] = arg.split("=")[1]
        if arg.lower().startswith("MAC=".lower()) or \
            arg.lower().startswith("instance_id=".lower()) or \
            arg.lower().startswith("hw_addr=".lower()) or \
            arg.lower().startswith("worker_id=".lower()):
            config["mac"] = arg.split("=")[1]
        if arg.lower().startswith("IP=".lower()):
            config["ip"] = arg.split("=")[1]
        if arg.lower().startswith("ID=".lower()) or arg.lower().startswith("plan=".lower()):
            config["id"] = arg.split("=")[1]
    logging.info(f"read_config_from_cmdline: {config}")
    return config


def main():
    basic_logging_config()
    
    logging.info("starting to run inside hwinfo")
    logging.info(os.system("lsblk"))
    logging.info(os.system("df -h"))
    # os.system(f"echo 'SELF_TEST_BASE_URL=http://labgw:50007 MAC=0c:c4:7a:85:7d:d6 IP=192.168.16.174 ID=rack02-server75' > {cmdline_path}")
    # we will try to read config from cmdline first, then from env vars
    # vars will be used if cmdline is empty
    config = read_config_from_cmdline()
    env_vars_config = read_config_env_vars()
    for k, v in env_vars_config.items():
        if v:
            logging.info(f"update config[{k}]: with {v}")
            config[k] = v
    config.verify()

    tries = 0
    while tries < 10:
        try:
            self_test_data = hwinfo.HWinfo().run(config["self_test_base_url"])
            msg = dict(info=self_test_data,
            mac=config["mac"],
            ip=config["ip"],
            id=config["id"])
            url = f"{config['self_test_base_url']}/{config['id']}?set_checked_in=true"
            logging.info(f"url: {url}, msg: {json.dumps(msg, indent=2)}")
            resp = requests.post(url, json=msg)
            resp.raise_for_status()
            break
        except requests.exceptions.ConnectionError as e:
            logging.error(f"error: {e}")
            tries += 1
            time.sleep(60)
        except urllib3.exceptions.MaxRetryError as e:
            logging.error(f"error: {e}")
            tries += 1
            time.sleep(60)
        except Exception as e:
            logging.error(f"error: type: {type(e)} {e}")
            tries += 1
            time.sleep(60)

    logging.info(f"going to sleep for 1h before retry")
    time.sleep(60*60)

# def main():
#     basic_logging_config()
    
#     logging.info("starting to run inside hwinfo")
#     # os.system(f"echo 'SELF_TEST_BASE_URL=http://labgw:50007 MAC=0c:c4:7a:85:7d:d6 IP=192.168.16.174 ID=rack02-server75' > {cmdline_path}")
#     # we will try to read config from cmdline first, then from env vars
#     # vars will be used if cmdline is empty
#     config = read_config_from_cmdline()
#     env_vars_config = read_config_env_vars()
#     for k, v in env_vars_config.items():
#         if v:
#             logging.info(f"update config[{k}]: with {v}")
#             config[k] = v
#     config.verify()

#     http = urllib3.PoolManager()
#     retries = Retry(total=10, backoff_factor=0.5)
#     try:
#         self_test_data = hwinfo.HWinfo().run(config["self_test_base_url"])
#         msg = dict(info=self_test_data,
# 		   mac=config["mac"],
# 		   ip=config["ip"],
# 		   id=config["id"])
#         #url = f"{config['self_test_base_url']}/{config['id']}?set_checked_in=true"
#         url = f"{config['self_test_base_url']}/{config['id']}"
#         resp = http.request('POST', url, json=msg, retries=retries)
#         resp.raise_for_status()
#     except Exception as e:
#         logging.error("error: ", e)


if __name__ == '__main__':
	main()
