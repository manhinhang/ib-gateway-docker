import os
import subprocess

import pytest
from ib_insync import IB, util, Forex

IMAGE_NAME = os.environ['IMAGE_NAME']

@pytest.fixture(scope='function')
def ib_docker(request):
    account = os.environ['IB_ACCOUNT']
    password = os.environ['IB_PASSWORD']
    trading_mode = os.environ['TRADING_MODE']

    # run a container
    docker_id = subprocess.check_output(
        ['docker', 'run', 
        '--env', 'IB_ACCOUNT={}'.format(account),
        '--env', 'IB_PASSWORD={}'.format(password),
        '--env', 'TRADING_MODE={}'.format(trading_mode),
        '-p', '4002:4002',
        '-d', IMAGE_NAME]).decode().strip()
    
    # at the end of the test suite, destroy the container
    def remove_container():
        subprocess.check_call(['docker', 'rm', '-f', docker_id])
    request.addfinalizer(remove_container)
    yield docker_id


CONNECT_RETRY_EXCEPTIONS = (
    ConnectionError, ConnectionRefusedError, OSError, TimeoutError,
)


def _connect_with_retry(ib, host, port, client_id, wait_seconds):
    """Poll-connect to the gateway until it accepts or `wait_seconds` elapse."""
    while not ib.isConnected() and wait_seconds > 0:
        try:
            IB.sleep(1)
            ib.connect(host, port, clientId=client_id)
        except CONNECT_RETRY_EXCEPTIONS:
            pass
        wait_seconds -= 1


def test_ibgw_interactive(ib_docker):
    ib = IB()
    _connect_with_retry(ib, 'localhost', 4002, client_id=998, wait_seconds=120)

    contract = Forex('EURUSD')
    bars = ib.reqHistoricalData(
        contract, endDateTime='', durationStr='30 D',
        barSizeSetting='1 hour', whatToShow='MIDPOINT', useRTH=True)

    print(util.df(bars))


def test_ibgw_restart(ib_docker):
    subprocess.check_output(
        ['docker', 'container', 'stop', ib_docker]).decode().strip()
    subprocess.check_output(
        ['docker', 'container', 'start', ib_docker]).decode().strip()

    ib = IB()
    _connect_with_retry(ib, 'localhost', 4002, client_id=998, wait_seconds=60)

    contract = Forex('EURUSD')
    bars = ib.reqHistoricalData(
        contract, endDateTime='', durationStr='30 D',
        barSizeSetting='1 hour', whatToShow='MIDPOINT', useRTH=True)

    print(util.df(bars))
