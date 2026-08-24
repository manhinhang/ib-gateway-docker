"""Tests for the second-factor / diagnostics settings start.sh injects into
IBC's config.ini.

These assert on the *config file the container produced*, not on a successful
IBKR login, so they need no real credentials and no network. Each test starts a
container with deliberately invalid credentials and inspects /root/ibc/config.ini
before IB Gateway gets anywhere near a login.

Covers the env vars added for 2FA handling:
  IBC_SECOND_FACTOR_DEVICE
  IBC_RELOGIN_AFTER_2FA_TIMEOUT
  IBC_LOG_STRUCTURE_SCOPE / IBC_LOG_STRUCTURE_WHEN
"""
import os
import subprocess

import pytest

IMAGE_NAME = os.environ['IMAGE_NAME']

IBC_INI = '/root/ibc/config.ini'


def run_container(env=None):
    """Start a detached container with dummy credentials and return its id.

    Credentials are intentionally invalid: these tests only read the generated
    config, and a real login would need a live IBKR account.
    """
    cmd = [
        'docker', 'run',
        '--env', 'IB_ACCOUNT=test',
        '--env', 'IB_PASSWORD=test',
        '--env', 'TRADING_MODE=paper',
    ]
    for key, value in (env or {}).items():
        cmd += ['--env', '{}={}'.format(key, value)]
    cmd += ['-d', IMAGE_NAME]
    return subprocess.check_output(cmd).decode().strip()


def read_setting(docker_id, key, timeout=90):
    """Return the value of `key` in the container's IBC config.

    The image ships a config.ini that already contains every key, and start.sh
    rewrites the values in place at boot. So "the key exists" is true from the
    first instant and cannot be used as a readiness signal — polling on that
    would race and read the pre-injection value.

    Instead, wait for the marker start.sh logs *after* it finishes its config
    rewrites, then read. `IbLoginId` is the last of the injected settings.
    """
    from conftest import wait_until

    def config_injected():
        logs = subprocess.run(['docker', 'logs', docker_id],
                              capture_output=True)
        combined = logs.stdout.decode() + logs.stderr.decode()
        # start.sh dumps the effective settings via IBC once it launches, and
        # IBC echoes IbLoginId as part of that dump. Its presence means every
        # sed injection above it has already run.
        return 'IbLoginId' in combined

    wait_until(config_injected, timeout=timeout,
               description='start.sh finished injecting {}'.format(IBC_INI))

    line = subprocess.check_output(
        ['docker', 'exec', docker_id, 'grep', '-m1', '^{}='.format(key), IBC_INI]
    ).decode().strip()
    # "Key=value" -> "value"; value may legitimately be empty or contain '='.
    return line.split('=', 1)[1]


@pytest.fixture
def container(request):
    """Factory fixture: start a container per test, always clean it up."""
    started = []

    def _start(env=None):
        docker_id = run_container(env)
        started.append(docker_id)
        return docker_id

    def cleanup():
        for docker_id in started:
            subprocess.call(['docker', 'rm', '-f', docker_id],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    request.addfinalizer(cleanup)
    return _start


def test_relogin_after_2fa_timeout_defaults_to_yes(container):
    """The image must ship ReloginAfterSecondFactorAuthenticationTimeout=yes.

    With 'no' (IBC's upstream default) a missed 2FA prompt leaves IB Gateway
    parked at the dialog forever: IBC's reloginPermitted() gates the whole
    timeout path on this, so TWOFA_TIMEOUT_ACTION never fires.
    """
    docker_id = container()
    assert read_setting(
        docker_id, 'ReloginAfterSecondFactorAuthenticationTimeout') == 'yes'


def test_relogin_after_2fa_timeout_can_be_overridden(container):
    docker_id = container({'IBC_RELOGIN_AFTER_2FA_TIMEOUT': 'no'})
    assert read_setting(
        docker_id, 'ReloginAfterSecondFactorAuthenticationTimeout') == 'no'


def test_invalid_relogin_value_fails_fast(container):
    """A typo must stop the container rather than silently degrade 2FA handling."""
    docker_id = container({'IBC_RELOGIN_AFTER_2FA_TIMEOUT': 'maybe'})
    exit_code = subprocess.check_output(
        ['docker', 'wait', docker_id]).decode().strip()
    assert exit_code == '1'
    logs = subprocess.run(['docker', 'logs', docker_id],
                          capture_output=True).stderr.decode()
    assert 'IBC_RELOGIN_AFTER_2FA_TIMEOUT' in logs


def test_second_factor_device_default(container):
    docker_id = container()
    assert read_setting(docker_id, 'SecondFactorDevice') == 'IB Key'


def test_second_factor_device_accepts_multiword_value(container):
    """Device names contain spaces, and the value must survive sed injection."""
    docker_id = container({'IBC_SECOND_FACTOR_DEVICE': 'Security Code Card'})
    assert read_setting(docker_id, 'SecondFactorDevice') == 'Security Code Card'


def test_second_factor_device_can_be_cleared(container):
    """Empty must mean "do not preselect".

    Passkey-only accounts have no "IB Key" entry, so forcing the image default
    would make IBC select nothing and stall at the device list.
    """
    docker_id = container({'IBC_SECOND_FACTOR_DEVICE': ''})
    assert read_setting(docker_id, 'SecondFactorDevice') == ''


def test_dialog_logging_off_by_default(container):
    """Upstream defaults stay in place unless explicitly opted into."""
    docker_id = container()
    assert read_setting(docker_id, 'LogStructureScope') == 'known'
    assert read_setting(docker_id, 'LogStructureWhen') == 'never'


def test_dialog_logging_can_be_enabled(container):
    docker_id = container({
        'IBC_LOG_STRUCTURE_SCOPE': 'all',
        'IBC_LOG_STRUCTURE_WHEN': 'activate',
    })
    assert read_setting(docker_id, 'LogStructureScope') == 'all'
    assert read_setting(docker_id, 'LogStructureWhen') == 'activate'
