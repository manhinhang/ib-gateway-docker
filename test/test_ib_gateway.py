import pytest
import subprocess
import testinfra
import os

IMAGE_NAME='ib_gateway'
IB_GATEWAY_VERSION=972
account = os.environ['IB_ACCOUNT']
password = os.environ['IB_PASSWORD']

# scope='session' uses the same container for all the tests;
# scope='function' uses a new container per test function.
@pytest.fixture(scope='function')
def host(request):
    # build local ./Dockerfile
    subprocess.check_call(['docker', 'build', '-t', IMAGE_NAME, '.'])
    # run a container
    docker_id = subprocess.check_output(
        ['docker', 'run', '-d', IMAGE_NAME]).decode().strip()
    # return a testinfra connection to the container
    yield testinfra.get_host("docker://" + docker_id)
    # at the end of the test suite, destroy the container
    subprocess.check_call(['docker', 'rm', '-f', docker_id])

def test_ibgateway_version(host):
    version = int(host.run("ls /root/Jts/ibgateway").stdout)
    assert version == IB_GATEWAY_VERSION

def test_ibc(host):
    cmd = host.run("pip install ib_insync")
    assert cmd.rc == 0
    script = """from ib_insync import *
ibc = IBC({}, gateway=True, tradingMode='paper', userid='{}', password='{}')
ibc.start()
""".format(IB_GATEWAY_VERSION, account, password)
    print('script', script)
    cmd = host.run("python -c \"{}\"".format(script))
    assert cmd.rc == 0

    script = """from ib_insync import *
ibc = IBC({}, gateway=True, tradingMode='paper', userid='{}', password='{}')
ibc.terminate()
""".format(IB_GATEWAY_VERSION, account, password)
    assert cmd.rc == 0

def test_ib_connect(host):
    cmd = host.run("pip install ib_insync")
    assert cmd.rc == 0

    script = """from ib_insync import *
ibc = IBC({}, gateway=True, tradingMode='paper', userid='{}', password='{}')
ibc.start()
""".format(IB_GATEWAY_VERSION, account, password)
    cmd = host.run("python -c \"{}\"".format(script))
    assert cmd.rc == 0

    script = """from ib_insync import *
IB.sleep(120)
ib = IB()
ib.connect('localhost', 4001, clientId=1)
ib.disconnect()
"""
    cmd = host.run("python -c \"{}\"".format(script))
    assert cmd.rc == 0
    
