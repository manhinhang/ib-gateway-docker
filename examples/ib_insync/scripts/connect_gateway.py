from ib_insync import IB, util, Forex

if __name__ == "__main__":
    ib = IB()
    # 4002 is the host-exposed port (4001 is internal-only via socat).
    # clientId 998 avoids collision with the healthcheck CLI's default 999.
    ib.connect('localhost', 4002, clientId=998)
    contract = Forex('EURUSD')
    bars = ib.reqHistoricalData(
        contract, endDateTime='', durationStr='30 D',
        barSizeSetting='1 hour', whatToShow='MIDPOINT', useRTH=True)

    # convert to pandas dataframe:
    df = util.df(bars)
    print(df)
