from ib_insync import IBC, IB
import os
import logging
import signal

def ping():
    def timeout_handler(signum, frame):
        signal.alarm(0)
        raise TimeoutError('IB gateway timed out, please check your account & password')
    signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(120)

    ib = IB()
    while not ib.isConnected():
        try:
            IB.sleep(1)
            ib.connect('localhost', 4001, clientId=1)
        except (ConnectionRefusedError, OSError) as e:
            if type(e) is TimeoutError:
                raise e
            logging.warning('Still waiting gateway connection..({})'.format(e))
    
    ib.disconnect()

if __name__ == "__main__":
    ib_gateway_version = int(os.listdir("/root/Jts/ibgateway")[0])
    account = os.environ['IB_ACCOUNT']
    password = os.environ['IB_PASSWORD']
    trade_mode = os.environ['TRADE_MODE']
    ibc = IBC(ib_gateway_version, gateway=True, tradingMode=trade_mode, userid=account, password=password)
    ibc.start()
    ping()
    logging.info('IB gateway is ready.')
    
