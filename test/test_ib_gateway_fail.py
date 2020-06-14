import pytest
import subprocess
import testinfra
import os
import time

IMAGE_NAME = os.environ['IMAGE_NAME']

# scope='session' uses the same container for all the tests;
# scope='function' uses a new container per test function.
@pytest.fixture(scope='session')
def host(request):
    account = 'test'
    password = 'test'
    trade_mode = 'paper'

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

def test_ib_connect_fail(host):
    script = """
from ib_insync import *
IB.sleep(60)
ib = IB()
ib.connect('localhost', 4001, clientId=1)
ib.disconnect()
"""
    cmd = host.run("python -c \"{}\"".format(script))
    assert cmd.rc == 1
