import pytest
import os
import subprocess
import time
from ib_insync import IB, util, Forex
import asyncio

IMAGE_NAME = os.environ['IMAGE_NAME']

@pytest.fixture(scope='function')
def ib_docker():
    account = os.environ['IB_ACCOUNT']
    password = os.environ['IB_PASSWORD']
    trade_mode = os.environ['TRADE_MODE']

    # run a container
    docker_id = subprocess.check_output(
        ['docker', 'run', 
        '--env', 'IB_ACCOUNT={}'.format(account),
        '--env', 'IB_PASSWORD={}'.format(password),
        '--env', 'TRADE_MODE={}'.format(trade_mode),
        '-p', '4002:4002',
        '-d', IMAGE_NAME, 
        "tail", "-f", "/dev/null"]).decode().strip()
    yield docker_id
    subprocess.check_call(['docker', 'rm', '-f', docker_id])


def test_ibgw_interactive(ib_docker):
    ib = IB()
    wait = 120
    while not ib.isConnected():
        try:
            IB.sleep(1)
            ib.connect('localhost', 4002, clientId=998)
        except:
            pass
        wait -= 1
        if wait <= 0:
            break
    
    contract = Forex('EURUSD')
    bars = ib.reqHistoricalData(
        contract, endDateTime='', durationStr='30 D',
        barSizeSetting='1 hour', whatToShow='MIDPOINT', useRTH=True)

    # convert to pandas dataframe:
    df = util.df(bars)
    print(df)
    
def test_ibgw_restart(ib_docker):

    subprocess.check_output(
        ['docker', 'container', 'stop', ib_docker]).decode().strip()
    subprocess.check_output(
        ['docker', 'container', 'start', ib_docker]).decode().strip()
    
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

    # convert to pandas dataframe:
    df = util.df(bars)
    print(df)
