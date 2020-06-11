import pytest
import subprocess
import testinfra
import os

IMAGE_NAME='ib-gateway-docker'
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
        ['docker', 'run', '-d', IMAGE_NAME, "tail", "-f", "/dev/null"]).decode().strip()
    # return a testinfra connection to the container
    yield testinfra.get_host("docker://" + docker_id)
    # at the end of the test suite, destroy the container
    subprocess.check_call(['docker', 'rm', '-f', docker_id])

def test_ibgateway_version(host):
    int(host.run("ls /root/Jts/ibgateway").stdout)

def test_ibc(host):
    ib_gateway_version = int(host.run("ls /root/Jts/ibgateway").stdout)
    cmd = host.run("pip install ib_insync")
    assert cmd.rc == 0
    script = """from ib_insync import *
ibc = IBC({}, gateway=True, tradingMode='paper', userid='{}', password='{}')
ibc.start()
""".format(ib_gateway_version, account, password)
    print('script', script)
    cmd = host.run("python -c \"{}\"".format(script))
    assert cmd.rc == 0

def test_ib_connect(host):
    ib_gateway_version = int(host.run("ls /root/Jts/ibgateway").stdout)
    cmd = host.run("pip install ib_insync")
    assert cmd.rc == 0

    script = """from ib_insync import *
ibc = IBC({}, gateway=True, tradingMode='paper', userid='{}', password='{}')
ibc.start()
""".format(ib_gateway_version, account, password)
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
    
