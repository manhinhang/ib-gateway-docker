# Example for starting up & connect IB Gateway

This example showing how to using [ib_insync](https://github.com/erdewit/ib_insync) library to connect `IB Gateway` 

Python script

| File | Description |
| - | - |
| [connect_gateway.py](scripts/connect_gateway.py) | connect `IB Gateway` and retrieve historical data |

## Docker run command
```bash
export TRADE_MODE=#paper or live
export IB_ACCOUNT=# your interactive brokers account name
export IB_PASSWORD=# your interactive brokers account password

docker run --rm \
-e IB_ACCOUNT=$IB_ACCOUNT \
-e IB_PASSWORD=$IB_PASSWORD \
-e TRADE_MODE=$TRADE_MODE \
-p 4001:4002 \
manhinhang/ib-gateway-docker:latest tail -f /dev/null

pip install ib_insync pandas
python ib_insync/scripts/connect_gateway.py
```