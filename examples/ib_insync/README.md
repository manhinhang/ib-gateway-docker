# Example for starting up & connect IB Gateway

This example showing how starting up `IB Gateway` though [IBC](https://github.com/IbcAlpha/IBC) and using [ib_insync](https://github.com/erdewit/ib_insync) library to connect `IB Gateway` 

Python script

| File | Description |
| - | - |
| [bootstrap.py](bootstrap.py) | starting up `IB Gateway` |
| [connect_gateway.py](connect_gateway.py) | connect `IB Gateway` and retrieve historical data |

## Docker run command
```bash
export TRADE_MODE=paper
export IB_ACCOUNT=# your interactive brokers account name
export IB_PASSWORD=# your interactive brokers account password

docker run -v $(pwd)/bootstrap.py:/home/bootstrap.py \
-v $(pwd)/connect_gateway.py:/home/connect_gateway.py \
-d manhinhang/ib-gateway-docker:latest python /home/bootstrap.py && python /home/connect_gateway.py
```