# IB Gateway docker

![Build test](https://github.com/manhinhang/ib-gateway-docker/workflows/Build%20test/badge.svg?branch=master)
![Docker Pulls](https://img.shields.io/docker/pulls/manhinhang/ib-gateway-docker)

lightweight interactive brokers gateway docker

It's just pure `IB Gateway` and don't include any VNC service (for security reason, I don't like expose extra port)

This docker image just installed:

- [IB Gateway](https://www.interactivebrokers.com/en/index.php?f=16457) (972)

- [IBC](https://github.com/IbcAlpha/IBC) (3.8.2)

## Pull the Docker image from Docker Hub

```bash
docker pull manhinhang/ib-gateway-docker
```

## Build & Run locally

### Build docker image
```bash
docker build -t ib-gateway .
```

### Create a container from the image and run it
```bash
docker run -d manhinhang/ib-gateway-docker tail -f /dev/null
```

## Container usage example

This example will using [ib_insync](https://github.com/erdewit/ib_insync) to demonstrate how to connect `IB Gateway`

### Starting up ib gateway though [IBC](https://github.com/IbcAlpha/IBC)

[IBC](https://github.com/IbcAlpha/IBC) is a greate tools for managing `IB Gateway` and [ib_insync](https://github.com/erdewit/ib_insync) is also provided interface to interacting [IBC](https://github.com/IbcAlpha/IBC).

Example Code : [examples/ib_insync](./examples/ib_insync)

# Tests

The [test cases]((test/test_ib_gateway.py)) written with testinfra.

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

