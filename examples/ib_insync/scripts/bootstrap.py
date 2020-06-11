from ib_insync import IBC
import os
from os import listdir

if __name__ == "__main__":
    ib_gateway_version = int(listdir("ls /root/Jts/ibgateway")[0])
    account = os.environ['IB_ACCOUNT']
    password = os.environ['IB_PASSWORD']
    trade_mode = os.environ['TRADE_MODE']
    trade_mode='paper' # paper / live
    ibc = IBC(ib_gateway_version, gateway=True, tradingMode=trade_mode, userid=account, password=password)
    ibc.start()
