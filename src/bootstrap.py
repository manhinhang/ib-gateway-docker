from ib_insync import IBC, IB
import os
import logging
from ib_account import IBAccount

if __name__ == "__main__":
    ib_gateway_version = int(os.listdir("/root/Jts/ibgateway")[0])
    account = IBAccount.account()
    password = IBAccount.password()
    trade_mode = IBAccount.trade_mode()
    ibc = IBC(ib_gateway_version, gateway=True, tradingMode=trade_mode, userid=account, password=password)
    ibc.start()
    ib = IB()
    while not ib.isConnected():
        try:
            IB.sleep(1)
            ib.connect('localhost', 4001, clientId=1)
        except (ConnectionRefusedError, OSError) as e:
            logging.warning('Still waiting gateway connection..({})'.format(e))
    ib.disconnect()
    logging.info('IB gateway is ready.')
    
