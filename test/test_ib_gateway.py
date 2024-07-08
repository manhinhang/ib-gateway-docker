import pytest
import subprocess
import testinfra
import os
import time
import requests

IMAGE_NAME = os.environ['IMAGE_NAME']

def test_healthcheck():
    account = os.environ['IB_ACCOUNT']
    password = os.environ['IB_PASSWORD']
    trading_mode = os.environ['TRADING_MODE']

    # run a container
    docker_id = subprocess.check_output(
        ['docker', 'run', 
        '--env', 'IB_ACCOUNT={}'.format(account),
        '--env', 'IB_PASSWORD={}'.format(password),
        '--env', 'TRADING_MODE={}'.format(trading_mode),
        '-d', IMAGE_NAME]).decode().strip()
    time.sleep(30)
    assert subprocess.check_call(['docker', 'exec', docker_id, 'healthcheck']) == 0
    subprocess.check_call(['docker', 'rm', '-f', docker_id])

def test_healthcheck_api():
    account = os.environ['IB_ACCOUNT']
    password = os.environ['IB_PASSWORD']
    trading_mode = os.environ['TRADING_MODE']

    # run a container
    docker_id = subprocess.check_output(
        ['docker', 'run', 
        '--env', 'IB_ACCOUNT={}'.format(account),
        '--env', 'IB_PASSWORD={}'.format(password),
        '--env', 'TRADING_MODE={}'.format(trading_mode),
        '--env', 'HEALTHCHECK_API_ENABLE=true',
        '-p', '8080:8080',
        '-d', IMAGE_NAME]).decode().strip()
    time.sleep(30)
    response = requests.get("http://127.0.0.1:8080/healthcheck")
    assert response.ok
    subprocess.check_call(['docker', 'rm', '-f', docker_id])

def test_healthcheck_api_fail():
    account = 'test'
    password = 'test'
    trading_mode = os.environ['TRADING_MODE']

    # run a container
    docker_id = subprocess.check_output(
        ['docker', 'run', 
        '--env', 'IB_ACCOUNT={}'.format(account),
        '--env', 'IB_PASSWORD={}'.format(password),
        '--env', 'TRADING_MODE={}'.format(trading_mode),
        '--env', 'HEALTHCHECK_API_ENABLE=true',
        '-p', '8080:8080',
        '-d', IMAGE_NAME]).decode().strip()
    time.sleep(30)
    try:
        response = requests.get("http://127.0.0.1:8080/healthcheck")
        assert not response.ok
    except requests.exceptions.ConnectionError:
        pass
    subprocess.check_call(['docker', 'rm', '-f', docker_id])
