import subprocess


def run_cmd(cmd: str) -> str:
    r = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        raise Exception(r.stderr.decode('utf-8'))
    return r.stdout.decode('utf-8')