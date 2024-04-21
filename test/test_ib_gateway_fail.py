import pytest
import subprocess
import testinfra
import os
import time
import requests
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
        '-p', '8080:8080',
        '-d', IMAGE_NAME]).decode().strip()
    
    # at the end of the test suite, destroy the container
    def remove_container():
        subprocess.check_call(['docker', 'rm', '-f', docker_id])
    request.addfinalizer(remove_container)

    # return a testinfra connection to the container
    yield testinfra.get_host("docker://" + docker_id)


def test_ib_insync_connect_fail(host):
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

def test_healthcheck_fail(host):
    time.sleep(30)
    assert host.exists("healthcheck")
    assert host.run('/healthcheck/bin/healthcheck').rc == 1

def test_healthcheck_rest_fail(host):
    time.sleep(30)
    response = requests.get("http://127.0.0.1:8080/healthcheck")
    assert not response.ok