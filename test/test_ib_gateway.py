import os
import subprocess

import pytest
import requests

from conftest import wait_for_healthcheck, wait_for_rest_api

IMAGE_NAME = os.environ['IMAGE_NAME']


def test_healthcheck():
    account = os.environ['IB_ACCOUNT']
    password = os.environ['IB_PASSWORD']
    trading_mode = os.environ['TRADING_MODE']

    docker_id = subprocess.check_output(
        ['docker', 'run',
         '--env', f'IB_ACCOUNT={account}',
         '--env', f'IB_PASSWORD={password}',
         '--env', f'TRADING_MODE={trading_mode}',
         '-d', IMAGE_NAME]).decode().strip()
    try:
        wait_for_healthcheck(docker_id)
    finally:
        subprocess.check_call(['docker', 'rm', '-f', docker_id])


def test_healthcheck_api():
    account = os.environ['IB_ACCOUNT']
    password = os.environ['IB_PASSWORD']
    trading_mode = os.environ['TRADING_MODE']

    # SERVER_ADDRESS=0.0.0.0 opts into external exposure; the image now binds
    # to 127.0.0.1 by default.
    docker_id = subprocess.check_output(
        ['docker', 'run',
         '--env', f'IB_ACCOUNT={account}',
         '--env', f'IB_PASSWORD={password}',
         '--env', f'TRADING_MODE={trading_mode}',
         '--env', 'HEALTHCHECK_API_ENABLE=true',
         '--env', 'SERVER_ADDRESS=0.0.0.0',
         '-p', '8080:8080',
         '-d', IMAGE_NAME]).decode().strip()
    try:
        wait_for_rest_api()
        wait_for_healthcheck(docker_id)
        response = requests.get("http://127.0.0.1:8080/healthcheck", timeout=10)
        assert response.ok
    finally:
        subprocess.check_call(['docker', 'rm', '-f', docker_id])


def test_healthcheck_api_fail():
    account = 'test'
    password = 'test'
    trading_mode = os.environ['TRADING_MODE']

    docker_id = subprocess.check_output(
        ['docker', 'run',
         '--env', f'IB_ACCOUNT={account}',
         '--env', f'IB_PASSWORD={password}',
         '--env', f'TRADING_MODE={trading_mode}',
         '--env', 'HEALTHCHECK_API_ENABLE=true',
         '--env', 'SERVER_ADDRESS=0.0.0.0',
         '-p', '8080:8080',
         '-d', IMAGE_NAME]).decode().strip()
    try:
        # Spring Boot starts independently of the gateway, so /ready is
        # reachable even when login will eventually fail.
        wait_for_rest_api()
        response = requests.get("http://127.0.0.1:8080/healthcheck", timeout=10)
        assert not response.ok
    finally:
        subprocess.check_call(['docker', 'rm', '-f', docker_id])
