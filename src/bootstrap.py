from ib_insync import IBC, IB, Watchdog
import os
import logging
from ib_account import IBAccount
import signal

if __name__ == "__main__":
    ib_gateway_version = int(os.listdir("/root/Jts/ibgateway")[0])
    account = IBAccount.account()
    password = IBAccount.password()
    trade_mode = IBAccount.trade_mode()
    ibc = IBC(ib_gateway_version, gateway=True, tradingMode=trade_mode, userid=account, password=password)
    ib = IB()
    def onConnected():
        print(ib.accountValues())
    ib.connectedEvent += onConnected
    watchdog = Watchdog(ibc, ib, port=4001)
    watchdog.start()
    ib.run()
    logging.info('IB gateway is ready.')
    
