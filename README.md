# Interactive Brokers Gateway (IBG) Docker container for Guerrilla Trading Platform (GTP)

[![Build test](https://github.com/rylorin/ib-gateway-docker/workflows/Build%20test/badge.svg?branch=master)](https://github.com/rylorin/ib-gateway-docker/actions/workflows/build-test.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/rylorin/ib-gateway-docker)](https://hub.docker.com/r/rylorin/ib-gateway-docker)
[![GitHub](https://img.shields.io/github/license/rylorin/ib-gateway-docker)](https://github.com/rylorin/ib-gateway-docker/blob/develop/LICENSE)

This container is based on [work from manhinhang](https://github.com/manhinhang/ib-gateway-docker) with the following changes:
- VNC server added (can be activated upon user's choice). Because I want to be able to look at what is going on the gateway.
- Health-check based on Docker's native feature added. Because the container must be restarted if needed.

More information available on [Github repository](https://github.com/rylorin/ib-gateway-docker).

This docker image contains:

- [IB Gateway](https://www.interactivebrokers.com/en/index.php?f=16457) (10.12)

- [IBC](https://github.com/IbcAlpha/IBC) (3.14.0)

- [ib_insync](https://github.com/erdewit/ib_insync) (0.9.71)

- [google-cloud-secret-manager](https://github.com/googleapis/python-secret-manager) (2.11.1)

## Pull the Docker image from Docker Hub

```bash
docker pull rylorin/ib-gateway-docker
```

### Create a container from the image and run it
```bash
docker run -d \
--env IB_ACCOUNT= \ #YOUR_USER_ID 
--env IB_PASSWORD= \ #YOUR_PASSWORD  
--env TRADE_MODE= \ #paper or live 
--p 4002:4002 \ #brige IB gateway port to your local port 4002
rylorin/ib-gateway-docker tail -f /dev/null
```

---

## Build & Run locally

```bash
git clone https://github.com/rylorin/ib-gateway-docker.git
cd ib-gateway-docker
docker build -t ib-gateway-docker .
docker run -d \
--env IB_ACCOUNT= \ #YOUR_USER_ID 
--env IB_PASSWORD= \ #YOUR_PASSWORD  
--env TRADE_MODE= \ #paper or live 
ib-gateway-docker \
tail -f /dev/null
```


## Container usage example

| Example | Link | Description |
| - | - | - |
| ib_insync | [examples/ib_insync](./examples/ib_insync) | This example demonstrated how to connect `IB Gateway`
| google cloud secret manager | [examples/google_cloud_secret_manager](./examples/google_cloud_secret_manager) | retreive your interactive brokers account from google cloud secret manager |


# Tests

The [test cases](test/test_ib_gateway.py) written with testinfra.

Run the tests

```
pytest
```

# Github Actions for continuous integration

After forking `IB Gateway docker` repository, you need config your **interactive brokers** paper account & password in *github secret*

| Key | Description |
| - | - |
| IB_ACCOUNT | your paper account name |
| IB_PASSWORD | your paper account password |

# Other environment variable

| Variable Name | Description | Default value |
| - | - | - |
| IB_GATEWAY_PING_CLIENT_ID | Docker healthcheck client id | Random |
| IBGW_WATCHDOG_CLIENT_ID | IB client id used for Watchdog | Random |
| IBGW_WATCHDOG_CONNECT_TIMEOUT | Ref to [ib_insync.ibcontroller.Watchdog.connectTimeout](https://ib-insync.readthedocs.io/api.html#ib_insync.ibcontroller.Watchdog.connectTimeout) | 30 |
| IBGW_WATCHDOG_APP_STARTUP_TIME | [ib_insync.ibcontroller.Watchdog.appStartupTime](https://ib-insync.readthedocs.io/api.html#ib_insync.ibcontroller.Watchdog.appStartupTime) | 30 |
| IBGW_WATCHDOG_APP_TIMEOUT | Ref to [ib_insync.ibcontroller.Watchdog.appTimeout](https://ib-insync.readthedocs.io/api.html#ib_insync.ibcontroller.Watchdog.appTimeout) | 30 |
| IBGW_WATCHDOG_RETRY_DELAY | Ref to [ib_insync.ibcontroller.Watchdog.retryDelay](https://ib-insync.readthedocs.io/api.html#ib_insync.ibcontroller.Watchdog.retryDelay) | 2 |
| IBGW_WATCHDOG_PROBE_TIMEOUT | Ref to [ib_insync.ibcontroller.Watchdog.probeTimeout](https://ib-insync.readthedocs.io/api.html#ib_insync.ibcontroller.Watchdog.probeTimeout) | 4 |
| VNC_SERVER_PASSWORD | VNC server password. If no password provided then VNC server won't start | None |


# Disclaimer

This project is not affiliated with [Interactive Brokers Group, Inc.'s](https://www.interactivebrokers.com).

Good luck and enjoy.
