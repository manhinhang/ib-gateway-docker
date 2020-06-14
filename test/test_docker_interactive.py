import pytest
import os
import subprocess
import time
from ib_insync import IB, util, Forex
import asyncio

IMAGE_NAME = os.environ['IMAGE_NAME']

def test_ibgw_port(host):
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
    
    ib = IB()
    wait = 120
    while not ib.isConnected():
        try:
            IB.sleep(1)
            ib.connect('localhost', 4002, clientId=999)
        except (ConnectionRefusedError, OSError, asyncio.exceptions.TimeoutError):
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

    # at the end of the test suite, destroy the container
    subprocess.check_call(['docker', 'rm', '-f', docker_id])


