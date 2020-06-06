# IB Gateway docker

![Build test](https://github.com/manhinhang/ib-gateway-docker/workflows/Build%20test/badge.svg?branch=master)

lightweight interactive brokers gateway docker

It's just pure `IB Gateway` and don't include any VNC service (for security reason, I don't like expose extra port)

### Build docker image
```bash
docker build -t ib-gateway .
```

### Create a container from the image and run it
```bash
docker run -d ib-gateway
```

### Container usage example

This example will using [ib_insync](https://github.com/erdewit/ib_insync) to demonstrate how to connect `IB Gateway`

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

