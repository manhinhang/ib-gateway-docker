from ib_insync import IBC, IB, Watchdog
import os
import logging
import ib_account
import sys

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, stream=sys.stdout, format="[%(asctime)s]%(levelname)s:%(message)s")
    logging.info('start ib gateway...')
    logging.info('---ib gateway info---')
    twsPath = os.environ['twsPath']
    logging.info(f'twsPath {twsPath}')
    gatewayRootPath = "{}/ibgateway".format(twsPath)
    ib_gateway_version = int(os.listdir(gatewayRootPath)[0])
    gatewayPath = "{}/{}".format(gatewayRootPath, ib_gateway_version)
    logging.info("ib gateway version:{}".format(ib_gateway_version))
    logging.info("ib gateway path:{}".format(gatewayPath))
    logging.info('-------------------')
    ib_creds = ib_account.IBAccount()
    if ib_account.IBAccount.isEnabledGCPSecret() and ib_account.IBAccount.isEnabledFileSecret():
        # if both env vars are set, don't assume which is valid, and raise an exception
        raise Exception('Both GCP and File provider enabled. Only 1 cred provider may be enabled.')
    if ib_account.IBAccount.isEnabledGCPSecret():
        logging.info("GCP Credential config detected.. Attempting to retrieve creds..")
        ib_creds = ib_account.GCPIBAccount()
    elif ib_account.IBAccount.isEnabledFileSecret():
        logging.info("File Credentials config detected.. Attempting to retrieve creds..")
        ib_creds = ib_account.FileCredsIBAccount()
    else:
        logging.info("No Credentials provider defined.. Attempting to retrieve creds from env vars..")
        ib_creds = ib_account.IBAccount()
    account = ib_creds.account()
    password = ib_creds.password()
    trade_mode = ib_creds.trade_mode()
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
                        connectTimeout=int(os.environ['IBGW_WATCHDOG_CONNECT_TIMEOUT']),
                        appStartupTime=int(os.environ['IBGW_WATCHDOG_APP_STARTUP_TIME']),
                        appTimeout=int(os.environ['IBGW_WATCHDOG_APP_TIMEOUT']),
                        retryDelay=int(os.environ['IBGW_WATCHDOG_RETRY_DELAY']),
                        probeTimeout=int(os.environ['IBGW_WATCHDOG_PROBE_TIMEOUT']))


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
