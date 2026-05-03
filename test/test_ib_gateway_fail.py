import os
import subprocess

import pytest
import requests
import testinfra
from ib_insync import IB, Forex

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
    """With invalid credentials, ib_insync should never connect and
    historical-data requests should error."""
    ib = IB()
    wait = 60
    while not ib.isConnected() and wait > 0:
        try:
            IB.sleep(1)
            ib.connect('localhost', 4002, clientId=998)
        except (ConnectionError, ConnectionRefusedError, OSError, TimeoutError):
            pass
        wait -= 1

    contract = Forex('EURUSD')
    with pytest.raises(Exception):
        ib.reqHistoricalData(
            contract, endDateTime='', durationStr='30 D',
            barSizeSetting='1 hour', whatToShow='MIDPOINT', useRTH=True)


def test_healthcheck_fail(host):
    # The healthcheck binary is shipped in the image at build time, so it's
    # always present immediately. With bad creds the gateway never opens its
    # API port and the CLI exits 1 fast — no sleep needed.
    assert host.exists("healthcheck")
    assert host.run('/healthcheck/bin/healthcheck').rc == 1


def test_healthcheck_rest_fail(host):
    # HEALTHCHECK_API_ENABLE is not set in this fixture, so port 8080 is not
    # bound. We expect ConnectionError (or refused) immediately.
    with pytest.raises(requests.exceptions.RequestException):
        requests.get("http://127.0.0.1:8080/healthcheck", timeout=2)
