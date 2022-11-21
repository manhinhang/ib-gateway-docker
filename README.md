# IB Gateway docker

![Build test](https://github.com/manhinhang/ib-gateway-docker/workflows/Build%20test/badge.svg?branch=master)
[![Docker Pulls](https://img.shields.io/docker/pulls/manhinhang/ib-gateway-docker)](https://hub.docker.com/r/manhinhang/ib-gateway-docker)
[![GitHub](https://img.shields.io/github/license/manhinhang/ib-gateway-docker)](https://github.com/manhinhang/ib-gateway-docker/blob/develop/LICENSE)

lightweight interactive brokers gateway docker

It's just pure `IB Gateway` and don't include any VNC service (for security reason, I don't like expose extra port)

This docker image just installed:

- [IB Gateway](https://www.interactivebrokers.com/en/index.php?f=16457) (10.19)

- [IBC](https://github.com/IbcAlpha/IBC) (3.14.0)

- [ib_insync](https://github.com/erdewit/ib_insync) (0.9.71)

- [google-cloud-secret-manager](https://github.com/googleapis/python-secret-manager) (2.11.1)

## Pull the Docker image from Docker Hub

```bash
docker pull manhinhang/ib-gateway-docker
```

### Create a container from the image and run it
```bash
docker run -d \
--env IB_ACCOUNT= \ #YOUR_USER_ID 
--env IB_PASSWORD= \ #YOUR_PASSWORD  
--env TRADE_MODE= \ #paper or live 
--p 4002:4002 \ #brige IB gateway port to your local port 4002
manhinhang/ib-gateway-docker tail -f /dev/null
```

---

## Build & Run locally

```bash
git clone git@github.com:manhinhang/ib-gateway-docker.git
cd ib-gateway-docker
docker build --no-cache -t ib-gateway-docker .
docker run -d \
--env IB_ACCOUNT= \ #YOUR_USER_ID 
--env IB_PASSWORD= \ #YOUR_PASSWORD  
--env TRADE_MODE= \ #paper or live 
-p 4002:4002 \ #brige IB gateway port to your local port 4002
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
| IB_GATEWAY_PING_CLIENT_ID | ib gateway client id for pinging client status | 1 |
| IBGW_WATCHDOG_CONNECT_TIMEOUT | Ref to [ib_insync.ibcontroller.Watchdog.connectTimeout](https://ib-insync.readthedocs.io/api.html#ib_insync.ibcontroller.Watchdog.connectTimeout) | 30 |
| IBGW_WATCHDOG_APP_STARTUP_TIME | [ib_insync.ibcontroller.Watchdog.appStartupTime](https://ib-insync.readthedocs.io/api.html#ib_insync.ibcontroller.Watchdog.appStartupTime) | 30 |
| IBGW_WATCHDOG_APP_TIMEOUT | Ref to [ib_insync.ibcontroller.Watchdog.appTimeout](https://ib-insync.readthedocs.io/api.html#ib_insync.ibcontroller.Watchdog.appTimeout) | 30 |
| IBGW_WATCHDOG_RETRY_DELAY | Ref to [ib_insync.ibcontroller.Watchdog.retryDelay](https://ib-insync.readthedocs.io/api.html#ib_insync.ibcontroller.Watchdog.retryDelay) | 2 |
| IBGW_WATCHDOG_PROBE_TIMEOUT | Ref to [ib_insync.ibcontroller.Watchdog.probeTimeout](https://ib-insync.readthedocs.io/api.html#ib_insync.ibcontroller.Watchdog.probeTimeout) | 4 |


# Disclaimer

This project is not affiliated with [Interactive Brokers Group, Inc.'s](https://www.interactivebrokers.com).

Good luck and enjoy.

