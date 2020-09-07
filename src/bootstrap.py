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
    ib.connectedEvent += onConnected
    def onConnected():
        print(ib.accountValues())
    IB_PORT = int(os.environ['IBGW_PORT'])
    watchdog = Watchdog(ibc, ib, port=IB_PORT)
    watchdog.start()
    ib.run()
    logging.info('IB gateway is ready.')
    
