# IB Gateway docker

![Build test](https://github.com/manhinhang/ib-gateway-docker/workflows/Build%20test/badge.svg?branch=master)
[![Docker Pulls](https://img.shields.io/docker/pulls/manhinhang/ib-gateway-docker)](https://hub.docker.com/r/manhinhang/ib-gateway-docker)
[![GitHub](https://img.shields.io/github/license/manhinhang/ib-gateway-docker)](https://github.com/manhinhang/ib-gateway-docker/blob/develop/LICENSE)

lightweight interactive brokers gateway docker

It's just pure `IB Gateway` and don't include any VNC service (for security reason, I don't like expose extra port)

This docker image just installed:

- [IB Gateway](https://www.interactivebrokers.com/en/index.php?f=16457) (10.30.1x)

- [IBC](https://github.com/IbcAlpha/IBC) (3.22.0)

## Pull the Docker image from Docker Hub

```bash
docker pull manhinhang/ib-gateway-docker
```

### Create a container from the image and run it
```bash
docker run -d \
--env IB_ACCOUNT= \ #YOUR_USER_ID 
--env IB_PASSWORD= \ #YOUR_PASSWORD  
--env TRADING_MODE= \ #paper or live 
-p 4002:4002 \ #brige IB gateway port to your local port 4002
manhinhang/ib-gateway-docker
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
--env TRADING_MODE= \ #paper or live 
-p 4002:4002 \ #brige IB gateway port to your local port 4002
ib-gateway-docker
```


## Container usage example

| Example | Link | Description |
| - | - | - |
| ib_insync | [examples/ib_insync](./examples/ib_insync) | This example demonstrated how to connect `IB Gateway`


## Health check container

### API

Healthcheck via api call `http://localhost:8080/healthcheck`

Config `HEALTHCHECK_API_ENABLE=true` in environment variable to enable API

```bash
curl -f http://localhost:8080/healthcheck
```

- Docker compose example

```yaml
services:
 ib-gateway:
   image: manhinhang/ib-gateway-docker
   ports:
     - 4002:4002
   environment:
     - IB_ACCOUNT=$IB_ACCOUNT
     - IB_PASSWORD=$IB_PASSWORD
     - TRADING_MODE=$TRADING_MODE
     - HEALTHCHECK_API_ENABLE=true
   healthcheck:
       test: ["CMD", "curl", "-f", "http://localhost:8080/healthcheck"]
       interval: 60s
       timeout: 30s
       retries: 3
       start_period: 60s
```
### CLI 
Execute `healthcheck` to detect IB gateway haelth status

```bash
healthcheck
# output: Ping IB Gateway successful
echo $?
# output: 0
```

```bash
healthcheck
# output: Can not connect to IB Gateway
echo $?
# output: 1
```

- Docker compose example

```yaml
services:
 ib-gateway:
   image: manhinhang/ib-gateway-docker
   ports:
     - 4002:4002
   environment:
     - IB_ACCOUNT=$IB_ACCOUNT
     - IB_PASSWORD=$IB_PASSWORD
     - TRADING_MODE=$TRADING_MODE
   healthcheck:
       test: /healthcheck/bin/healthcheck
       interval: 60s
       timeout: 30s
       retries: 3
       start_period: 60s
```

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

# Disclaimer

This project is not affiliated with [Interactive Brokers Group, Inc.'s](https://www.interactivebrokers.com).

Good luck and enjoy.

