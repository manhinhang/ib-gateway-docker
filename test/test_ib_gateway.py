import pytest
import subprocess
import testinfra
import os

IMAGE_NAME = os.environ['IMAGE_NAME']

# scope='session' uses the same container for all the tests;
# scope='function' uses a new container per test function.
@pytest.fixture(scope='session')
def host(request):
    account = os.environ['IB_ACCOUNT']
    password = os.environ['IB_PASSWORD']
    trade_mode = os.environ['TRADE_MODE']

    # run a container
    docker_id = subprocess.check_output(
        ['docker', 'run', 
        '--env', 'IB_ACCOUNT={}'.format(account),
        '--env', 'IB_PASSWORD={}'.format(password),
        '--env', 'TRADE_MODE={}'.format(trade_mode),
        '-d', IMAGE_NAME, 
        "tail", "-f", "/dev/null"]).decode().strip()
    # return a testinfra connection to the container
    yield testinfra.get_host("docker://" + docker_id)
    # at the end of the test suite, destroy the container
    subprocess.check_call(['docker', 'rm', '-f', docker_id])

def test_ibgateway_version(host):
    int(host.run("ls /root/Jts/ibgateway").stdout)

def test_ib_connect(host):
    script = """
from ib_insync import *
from concurrent.futures import TimeoutError

ib = IB()
wait = 60
while not ib.isConnected():
    try:
        IB.sleep(1)
        ib.connect('localhost', 4002, clientId=999)
    except (ConnectionRefusedError, OSError, TimeoutError):
        pass
    wait -= 1
    if wait <= 0:
        break
ib.disconnect()
"""
    cmd = host.run("python -c \"{}\"".format(script))
    assert cmd.rc == 0
