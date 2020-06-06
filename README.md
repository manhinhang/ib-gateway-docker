# IB Gateway docker

![Build test](https://github.com/manhinhang/ib-gateway-docker/workflows/Build%20test/badge.svg?branch=master)

lightweight interactive brokers gateway docker

It's just pure `IB Gateway` and don't include any VNC service (for security reason, I don't like expose extra port)

This docker image just installed:

- [IB Gateway](https://www.interactivebrokers.com/en/index.php?f=16457) (972)

- [IBC](https://github.com/IbcAlpha/IBC) (3.8.2)

## Build & Run locally

### Build docker image
```bash
docker build -t ib-gateway .
```

### Create a container from the image and run it
```bash
docker run -d ib-gateway
```

## Container usage example

This example will using [ib_insync](https://github.com/erdewit/ib_insync) to demonstrate how to connect `IB Gateway`

---

### Starting up ib gateway though [IBC](https://github.com/IbcAlpha/IBC)

[IBC](https://github.com/IbcAlpha/IBC) is a greate tools for managing `IB Gateway` and [ib_insync](https://github.com/erdewit/ib_insync) is also provided interface to interacting [IBC](https://github.com/IbcAlpha/IBC).

Starting up the `IB Gateway`
```bash
export TRADE_MODE=paper
export IB_ACCOUNT=# your interactive brokers account name
export IB_PASSWORD=# your interactive brokers account password
docker run -p 4001:4001 -d ib-gateway /bin/bash -c "pip install ib_insync;python -c \"from ib_insync import *\nIBC(972, gateway=True, tradingMode='$TRADE_MODE', userid='$IB_ACCOUNT', password='$IB_PASSWORD').start()\""
```

Connect the `IB Gateway`
```python
from ib_insync import *
# util.startLoop()  # uncomment this line when in a notebook

ib = IB()
ib.connect('127.0.0.1', 4001, clientId=1)

contract = Forex('EURUSD')
bars = ib.reqHistoricalData(
    contract, endDateTime='', durationStr='30 D',
    barSizeSetting='1 hour', whatToShow='MIDPOINT', useRTH=True)

# convert to pandas dataframe:
df = util.df(bars)
print(df)
```

---

### interacting with docker container

Prepare python script and named `example.py`

```python
from ib_insync import *
account = # your interactive brokers account name
password = # your interactive brokers account password
trade_mode='paper' # paper / live
ibc = IBC(972, gateway=True, tradingMode=trade_mode, userid=account, password=password)
ibc.start()
IB.sleep(60)
ib = IB()
ib.connect('localhost', 4001, clientId=1)
contract = Forex('EURUSD')
bars = ib.reqHistoricalData(
    contract, endDateTime='', durationStr='30 D',
    barSizeSetting='1 hour', whatToShow='MIDPOINT', useRTH=True)

# convert to pandas dataframe:
df = util.df(bars)
print(df)
```

Run there command in terminal

```bash
docker_id=$(docker run -d ib-gateway)
docker exec $docker_id pip install ib_insync
docker exec $docker_id pip install pandas
docker cp example.py $docker_id:/home/example.py
docker exec $docker_id python /home/example.py
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

