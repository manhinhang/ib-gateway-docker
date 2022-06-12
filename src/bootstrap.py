from ib_insync import IBC, IB, Watchdog
import os
import logging
from ib_account import IBAccount
import sys

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, stream=sys.stdout, format="[%(asctime)s]%(levelname)s:%(message)s")
    logging.info('start ib gateway...')
    logging.info('---ib gateway info---')
    twsPath = os.environ['twsPath']
    logging.info('twsPath', twsPath)
    gatewayRootPath = "{}/ibgateway".format(twsPath)
    ib_gateway_version = int(os.listdir(gatewayRootPath)[0])
    gatewayPath = "{}/{}".format(gatewayRootPath, ib_gateway_version)
    logging.info("ib gateway version:{}".format(ib_gateway_version))
    logging.info("ib gateway path:{}".format(gatewayPath))
    logging.info('-------------------')
    account = IBAccount.account()
    password = IBAccount.password()
    trade_mode = IBAccount.trade_mode()
    ibc = IBC(ib_gateway_version, 
        gateway=True, 
        tradingMode=trade_mode, 
        userid=account, 
        password=password, 
        twsPath=twsPath)
    ib = IB()
    def onConnected():
        logging.info('IB gateway connected')
        logging.info(ib.accountValues())
            
    def onDisconnected():
        logging.info('IB gateway disconnected')
    ib.connectedEvent += onConnected
    ib.disconnectedEvent += onDisconnected
    watchdog = Watchdog(ibc, ib, port=4001, 
        connectTimeout=30, 
        appStartupTime=30, 
        appTimeout=30,
        retryDelay=30)
    def onWatchDogStarting(_):
        logging.info('WatchDog Starting...')
    def onWatchDogStarted(_):
        logging.info('WatchDog Started!')
    def onWatchDogStopping(_):
        logging.info('WatchDog Stopping...')
    def onWatchDogStopped(_):
        logging.info('WatchDog Stopped!')
    def onWatchDogSoftTimeout(_):
        logging.info('WatchDog soft timeout!')
    def onWatchDogHardTimeoutEvent(_):
        logging.info('WatchDog hard timeout!')
    watchdog.startingEvent += onWatchDogStarting
    watchdog.startedEvent += onWatchDogStarted
    watchdog.stoppingEvent += onWatchDogStopping
    watchdog.stoppedEvent += onWatchDogStopped
    watchdog.softTimeoutEvent += onWatchDogSoftTimeout
    watchdog.hardTimeoutEvent += onWatchDogHardTimeoutEvent
    watchdog.start()
    ib.run()
    logging.info('IB gateway is ready.')
    
