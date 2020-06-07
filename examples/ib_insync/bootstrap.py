from ib_insync import IBC
import os

if __name__ == "__main__":
    account = os.environ['IB_ACCOUNT']
    password = os.environ['IB_PASSWORD']
    trade_mode = os.environ['TRADE_MODE']
    trade_mode='paper' # paper / live
    ibc = IBC(972, gateway=True, tradingMode=trade_mode, userid=account, password=password)
    ibc.start()
