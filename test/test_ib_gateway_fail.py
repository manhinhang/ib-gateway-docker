import pytest
import subprocess
import testinfra
import os
import time
from ib_insync import IB, util, Forex

IMAGE_NAME = os.environ['IMAGE_NAME']

# scope='session' uses the same container for all the tests;
# scope='function' uses a new container per test function.
@pytest.fixture(scope='session')
def host(request):
    account = 'test'
    password = 'test'
    trading_mode = 'paper'

    # run a container
    docker_id = subprocess.check_output(
        ['docker', 'run', 
        '--env', 'IB_ACCOUNT={}'.format(account),
        '--env', 'IB_PASSWORD={}'.format(password),
        '--env', 'TRADING_MODE={}'.format(trading_mode),
        '-d', IMAGE_NAME, 
        "tail", "-f", "/dev/null"]).decode().strip()
    # return a testinfra connection to the container
    yield testinfra.get_host("docker://" + docker_id)
    # at the end of the test suite, destroy the container
    subprocess.check_call(['docker', 'rm', '-f', docker_id])

def test_ib_connect_fail(host):
    try:
        ib = IB()
        wait = 60
        while not ib.isConnected():
            try:
                IB.sleep(1)
                ib.connect('localhost', 4002, clientId=999)
            except:
                pass
            wait -= 1
            if wait <= 0:
                break
        
        contract = Forex('EURUSD')
        bars = ib.reqHistoricalData(
            contract, endDateTime='', durationStr='30 D',
            barSizeSetting='1 hour', whatToShow='MIDPOINT', useRTH=True)
        assert False
    except:
        pass

