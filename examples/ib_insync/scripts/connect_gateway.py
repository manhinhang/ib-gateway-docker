from ib_insync import IB, util, Forex

if __name__ == "__main__":
    ib = IB()
    ib.connect('localhost', 4001, clientId=999)
    contract = Forex('EURUSD')
    bars = ib.reqHistoricalData(
        contract, endDateTime='', durationStr='30 D',
        barSizeSetting='1 hour', whatToShow='MIDPOINT', useRTH=True)

    # convert to pandas dataframe:
    df = util.df(bars)
    print(df)
