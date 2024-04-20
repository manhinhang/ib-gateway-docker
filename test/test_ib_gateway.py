import pytest
import subprocess
import testinfra
import os

IMAGE_NAME = os.environ['IMAGE_NAME']

# scope='session' uses the same container for all the tests;
# scope='function' uses a new container per test function.
@pytest.fixture(scope='function')
def host(request):
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
    
    # at the end of the test suite, destroy the container
    def remove_container():
        subprocess.check_call(['docker', 'rm', '-f', docker_id])
    request.addfinalizer(remove_container)

    # return a testinfra connection to the container
    yield testinfra.get_host("docker://" + docker_id)

def test_heathcheck(host):
    assert host.exists("healthcheck")
    assert host.run('healthcheck').rc == 0
