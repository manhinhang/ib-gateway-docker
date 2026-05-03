"""Shared pytest helpers for the smoke-test suite.

Replaces fragile time.sleep(30) calls with poll-based readiness checks.
"""
import subprocess
import time

import pytest
import requests

DEFAULT_TIMEOUT_SECONDS = 120
DEFAULT_INTERVAL_SECONDS = 2


def wait_until(predicate, timeout=DEFAULT_TIMEOUT_SECONDS,
               interval=DEFAULT_INTERVAL_SECONDS, description="condition"):
    """Poll `predicate` every `interval` seconds until it returns truthy or
    `timeout` elapses. Fail the test with a clear message on timeout."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(interval)
    pytest.fail(f"Timed out after {timeout}s waiting for {description}")


def wait_for_healthcheck(docker_id, timeout=DEFAULT_TIMEOUT_SECONDS):
    """Block until `docker exec <id> healthcheck` exits 0."""

    def healthcheck_passes():
        return subprocess.call(
            ['docker', 'exec', docker_id, 'healthcheck'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ) == 0

    wait_until(
        healthcheck_passes, timeout=timeout,
        description=f"healthcheck CLI in container {docker_id[:12]}",
    )


def wait_for_rest_api(host="127.0.0.1", port=8080,
                      timeout=DEFAULT_TIMEOUT_SECONDS):
    """Block until GET http://host:port/ready returns 200. The /ready
    endpoint is independent of the IB gateway state — it confirms only that
    the Spring Boot server has bound the port."""
    url = f"http://{host}:{port}/ready"

    def ready_responds():
        try:
            return requests.get(url, timeout=2).status_code == 200
        except requests.exceptions.RequestException:
            return False

    wait_until(
        ready_responds, timeout=timeout,
        description=f"REST API at {url}",
    )
