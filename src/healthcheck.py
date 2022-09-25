#!/usr/local/bin/python
import os, random
from ib_insync import IB, util, Forex
from ib_account import IBAccount

if __name__ == "__main__":
    account = IBAccount.account()
    password = IBAccount.password()
    clientId = int(random.random() * 16382) + 1
    ib = IB()
    ib.connect('localhost', int(os.environ['IBGW_PORT']), clientId)
    contract = Forex('EURUSD')
    bars = ib.reqHistoricalData(
        contract, endDateTime='', durationStr='7 D',
        barSizeSetting='1 day', whatToShow='MIDPOINT', useRTH=True)
    print(bars[-1])
