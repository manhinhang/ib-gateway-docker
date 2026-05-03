package com.manhinhang.ibgatewaydocker.healthcheck

import com.ib.client.*
import com.ib.client.protobuf.*

/**
 * EWrapper implementation that captures the last error message reported by
 * the IB gateway via the error() callbacks. All other callbacks are no-ops.
 *
 * This file is GENERATED at build time from EWrapper.java by
 * generate-wrapper.sh. Do not edit by hand.
 */
class Wrapper : EWrapper {
    @Volatile
    var lastError: String? = null

    companion object {
        // 21xx codes are informational notices (data farm connection ok, etc.)
        // and 23xx are warnings, not failures. See IB API docs for full list.
        val INFORMATIONAL_ERROR_CODES = setOf(
            2104, 2106, 2107, 2108, 2110, 2119, 2137, 2150, 2157, 2158
        )
    }

    override fun tickPrice(tickerId: Int, field: Int, price: Double, attrib: TickAttrib?) {}
    override fun tickSize(tickerId: Int, field: Int, size: Decimal?) {}
    override fun tickOptionComputation(tickerId: Int, field: Int, tickAttrib: Int, impliedVol: Double, delta: Double, optPrice: Double, pvDividend: Double, gamma: Double, vega: Double, theta: Double, undPrice: Double) {}
    override fun tickGeneric(tickerId: Int, tickType: Int, value: Double) {}
    override fun tickString(tickerId: Int, tickType: Int, value: String?) {}
    override fun tickEFP(tickerId: Int, tickType: Int, basisPoints: Double, formattedBasisPoints: String?, impliedFuture: Double, holdDays: Int, futureLastTradeDate: String?, dividendImpact: Double, dividendsToLastTradeDate: Double) {}
    override fun orderStatus(orderId: Int, status: String?, filled: Decimal?, remaining: Decimal?, avgFillPrice: Double, permId: Long, parentId: Int, lastFillPrice: Double, clientId: Int, whyHeld: String?, mktCapPrice: Double) {}
    override fun openOrder(orderId: Int, contract: Contract?, order: Order?, orderState: OrderState?) {}
    override fun openOrderEnd() {}
    override fun updateAccountValue(key: String?, value: String?, currency: String?, accountName: String?) {}
    override fun updatePortfolio(contract: Contract?, position: Decimal?, marketPrice: Double, marketValue: Double, averageCost: Double, unrealizedPNL: Double, realizedPNL: Double, accountName: String?) {}
    override fun updateAccountTime(timeStamp: String?) {}
    override fun accountDownloadEnd(accountName: String?) {}
    override fun nextValidId(orderId: Int) {}
    override fun contractDetails(reqId: Int, contractDetails: ContractDetails?) {}
    override fun bondContractDetails(reqId: Int, contractDetails: ContractDetails?) {}
    override fun contractDetailsEnd(reqId: Int) {}
    override fun execDetails(reqId: Int, contract: Contract?, execution: Execution?) {}
    override fun execDetailsEnd(reqId: Int) {}
    override fun updateMktDepth(tickerId: Int, position: Int, operation: Int, side: Int, price: Double, size: Decimal?) {}
    override fun updateMktDepthL2(tickerId: Int, position: Int, marketMaker: String?, operation: Int, side: Int, price: Double, size: Decimal?, isSmartDepth: Boolean) {}
    override fun updateNewsBulletin(msgId: Int, msgType: Int, message: String?, origExchange: String?) {}
    override fun managedAccounts(accountsList: String?) {}
    override fun receiveFA(faDataType: Int, xml: String?) {}
    override fun historicalData(reqId: Int, bar: Bar?) {}
    override fun scannerParameters(xml: String?) {}
    override fun scannerData(reqId: Int, rank: Int, contractDetails: ContractDetails?, distance: String?, benchmark: String?, projection: String?, legsStr: String?) {}
    override fun scannerDataEnd(reqId: Int) {}
    override fun realtimeBar(reqId: Int, time: Long, open: Double, high: Double, low: Double, close: Double, volume: Decimal?, wap: Decimal?, count: Int) {}
    override fun currentTime(time: Long) {}
    override fun fundamentalData(reqId: Int, data: String?) {}
    override fun deltaNeutralValidation(reqId: Int, deltaNeutralContract: DeltaNeutralContract?) {}
    override fun tickSnapshotEnd(reqId: Int) {}
    override fun marketDataType(reqId: Int, marketDataType: Int) {}
    override fun commissionAndFeesReport(commissionAndFeesReport: CommissionAndFeesReport?) {}
    override fun position(account: String?, contract: Contract?, pos: Decimal?, avgCost: Double) {}
    override fun positionEnd() {}
    override fun accountSummary(reqId: Int, account: String?, tag: String?, value: String?, currency: String?) {}
    override fun accountSummaryEnd(reqId: Int) {}
    override fun verifyMessageAPI(apiData: String?) {}
    override fun verifyCompleted(isSuccessful: Boolean, errorText: String?) {}
    override fun verifyAndAuthMessageAPI(apiData: String?, xyzChallenge: String?) {}
    override fun verifyAndAuthCompleted(isSuccessful: Boolean, errorText: String?) {}
    override fun displayGroupList(reqId: Int, groups: String?) {}
    override fun displayGroupUpdated(reqId: Int, contractInfo: String?) {}
    override fun error(e: Exception?) {
        lastError = e?.message ?: e?.toString()
    }
    override fun error(str: String?) {
        lastError = str
    }
    override fun error(id: Int, errorTime: Long, errorCode: Int, errorMsg: String?, advancedOrderRejectJson: String?) {
        if (errorCode in INFORMATIONAL_ERROR_CODES) return
        lastError = "[${errorCode}] ${errorMsg}"
    }
    override fun connectionClosed() {}
    override fun connectAck() {}
    override fun positionMulti(reqId: Int, account: String?, modelCode: String?, contract: Contract?, pos: Decimal?, avgCost: Double) {}
    override fun positionMultiEnd(reqId: Int) {}
    override fun accountUpdateMulti(reqId: Int, account: String?, modelCode: String?, key: String?, value: String?, currency: String?) {}
    override fun accountUpdateMultiEnd(reqId: Int) {}
    override fun securityDefinitionOptionalParameter(reqId: Int, exchange: String?, underlyingConId: Int, tradingClass: String?, multiplier: String?, expirations: MutableSet<String>?, strikes: MutableSet<Double>?) {}
    override fun securityDefinitionOptionalParameterEnd(reqId: Int) {}
    override fun softDollarTiers(reqId: Int, tiers: Array<out SoftDollarTier>?) {}
    override fun familyCodes(familyCodes: Array<out FamilyCode>?) {}
    override fun symbolSamples(reqId: Int, contractDescriptions: Array<out ContractDescription>?) {}
    override fun historicalDataEnd(reqId: Int, startDateStr: String?, endDateStr: String?) {}
    override fun mktDepthExchanges(depthMktDataDescriptions: Array<out DepthMktDataDescription>?) {}
    override fun tickNews(tickerId: Int, timeStamp: Long, providerCode: String?, articleId: String?, headline: String?, extraData: String?) {}
    override fun smartComponents(reqId: Int, theMap: MutableMap<Int, MutableMap.MutableEntry<String, Char>>?) {}
    override fun tickReqParams(tickerId: Int, minTick: Double, bboExchange: String?, snapshotPermissions: Int) {}
    override fun newsProviders(newsProviders: Array<out NewsProvider>?) {}
    override fun newsArticle(requestId: Int, articleType: Int, articleText: String?) {}
    override fun historicalNews(requestId: Int, time: String?, providerCode: String?, articleId: String?, headline: String?) {}
    override fun historicalNewsEnd(requestId: Int, hasMore: Boolean) {}
    override fun headTimestamp(reqId: Int, headTimestamp: String?) {}
    override fun histogramData(reqId: Int, items: MutableList<HistogramEntry>?) {}
    override fun historicalDataUpdate(reqId: Int, bar: Bar?) {}
    override fun rerouteMktDataReq(reqId: Int, conId: Int, exchange: String?) {}
    override fun rerouteMktDepthReq(reqId: Int, conId: Int, exchange: String?) {}
    override fun marketRule(marketRuleId: Int, priceIncrements: Array<out PriceIncrement>?) {}
    override fun pnl(reqId: Int, dailyPnL: Double, unrealizedPnL: Double, realizedPnL: Double) {}
    override fun pnlSingle(reqId: Int, pos: Decimal?, dailyPnL: Double, unrealizedPnL: Double, realizedPnL: Double, value: Double) {}
    override fun historicalTicks(reqId: Int, ticks: MutableList<HistoricalTick>?, done: Boolean) {}
    override fun historicalTicksBidAsk(reqId: Int, ticks: MutableList<HistoricalTickBidAsk>?, done: Boolean) {}
    override fun historicalTicksLast(reqId: Int, ticks: MutableList<HistoricalTickLast>?, done: Boolean) {}
    override fun tickByTickAllLast(reqId: Int, tickType: Int, time: Long, price: Double, size: Decimal?, tickAttribLast: TickAttribLast?, exchange: String?, specialConditions: String?) {}
    override fun tickByTickBidAsk(reqId: Int, time: Long, bidPrice: Double, askPrice: Double, bidSize: Decimal?, askSize: Decimal?, tickAttribBidAsk: TickAttribBidAsk?) {}
    override fun tickByTickMidPoint(reqId: Int, time: Long, midPoint: Double) {}
    override fun orderBound(permId: Long, clientId: Int, orderId: Int) {}
    override fun completedOrder(contract: Contract?, order: Order?, orderState: OrderState?) {}
    override fun completedOrdersEnd() {}
    override fun replaceFAEnd(reqId: Int, text: String?) {}
    override fun wshMetaData(reqId: Int, dataJson: String?) {}
    override fun wshEventData(reqId: Int, dataJson: String?) {}
    override fun historicalSchedule(reqId: Int, startDateTime: String?, endDateTime: String?, timeZone: String?, sessions: MutableList<HistoricalSession>?) {}
    override fun userInfo(reqId: Int, whiteBrandingId: String?) {}
    override fun currentTimeInMillis(timeInMillis: Long) {}
    override fun orderStatusProtoBuf(orderStatusProto: OrderStatusProto.OrderStatus?) {}
    override fun openOrderProtoBuf(openOrderProto: OpenOrderProto.OpenOrder?) {}
    override fun openOrdersEndProtoBuf(openOrdersEndProto: OpenOrdersEndProto.OpenOrdersEnd?) {}
    override fun errorProtoBuf(errorMessageProto: ErrorMessageProto.ErrorMessage?) {}
    override fun execDetailsProtoBuf(executionDetailsProto: ExecutionDetailsProto.ExecutionDetails?) {}
    override fun execDetailsEndProtoBuf(executionDetailsEndProto: ExecutionDetailsEndProto.ExecutionDetailsEnd?) {}
    override fun completedOrderProtoBuf(completedOrderProto: CompletedOrderProto.CompletedOrder?) {}
    override fun completedOrdersEndProtoBuf(completedOrdersEndProto: CompletedOrdersEndProto.CompletedOrdersEnd?) {}
    override fun orderBoundProtoBuf(orderBoundProto: OrderBoundProto.OrderBound?) {}
    override fun contractDataProtoBuf(contractDataProto: ContractDataProto.ContractData?) {}
    override fun bondContractDataProtoBuf(contractDataProto: ContractDataProto.ContractData?) {}
    override fun contractDataEndProtoBuf(contractDataEndProto: ContractDataEndProto.ContractDataEnd?) {}
    override fun tickPriceProtoBuf(tickPriceProto: TickPriceProto.TickPrice?) {}
    override fun tickSizeProtoBuf(tickSizeProto: TickSizeProto.TickSize?) {}
    override fun tickOptionComputationProtoBuf(tickOptionComputationProto: TickOptionComputationProto.TickOptionComputation?) {}
    override fun tickGenericProtoBuf(tickGenericProto: TickGenericProto.TickGeneric?) {}
    override fun tickStringProtoBuf(tickStringProto: TickStringProto.TickString?) {}
    override fun tickSnapshotEndProtoBuf(tickSnapshotEndProto: TickSnapshotEndProto.TickSnapshotEnd?) {}
    override fun updateMarketDepthProtoBuf(marketDepthProto: MarketDepthProto.MarketDepth?) {}
    override fun updateMarketDepthL2ProtoBuf(marketDepthL2Proto: MarketDepthL2Proto.MarketDepthL2?) {}
    override fun marketDataTypeProtoBuf(marketDataTypeProto: MarketDataTypeProto.MarketDataType?) {}
    override fun tickReqParamsProtoBuf(tickReqParamsProto: TickReqParamsProto.TickReqParams?) {}
    override fun updateAccountValueProtoBuf(accounValueProto: AccountValueProto.AccountValue?) {}
    override fun updatePortfolioProtoBuf(portfolioValueProto: PortfolioValueProto.PortfolioValue?) {}
    override fun updateAccountTimeProtoBuf(accountUpdateTimeProto: AccountUpdateTimeProto.AccountUpdateTime?) {}
    override fun accountDataEndProtoBuf(accountDataEndProto: AccountDataEndProto.AccountDataEnd?) {}
    override fun managedAccountsProtoBuf(managedAccountsProto: ManagedAccountsProto.ManagedAccounts?) {}
    override fun positionProtoBuf(positionProto: PositionProto.Position?) {}
    override fun positionEndProtoBuf(positionEndProto: PositionEndProto.PositionEnd?) {}
    override fun accountSummaryProtoBuf(accountSummaryProto: AccountSummaryProto.AccountSummary?) {}
    override fun accountSummaryEndProtoBuf(accountSummaryEndProto: AccountSummaryEndProto.AccountSummaryEnd?) {}
    override fun positionMultiProtoBuf(positionMultiProto: PositionMultiProto.PositionMulti?) {}
    override fun positionMultiEndProtoBuf(positionMultiEndProto: PositionMultiEndProto.PositionMultiEnd?) {}
    override fun accountUpdateMultiProtoBuf(accountUpdateMultiProto: AccountUpdateMultiProto.AccountUpdateMulti?) {}
    override fun accountUpdateMultiEndProtoBuf(accountUpdateMultiEndProto: AccountUpdateMultiEndProto.AccountUpdateMultiEnd?) {}
    override fun historicalDataProtoBuf(historicalDataProto: HistoricalDataProto.HistoricalData?) {}
    override fun historicalDataUpdateProtoBuf(historicalDataUpdateProto: HistoricalDataUpdateProto.HistoricalDataUpdate?) {}
    override fun historicalDataEndProtoBuf(historicalDataEndProto: HistoricalDataEndProto.HistoricalDataEnd?) {}
    override fun realTimeBarTickProtoBuf(realTimeBarTickProto: RealTimeBarTickProto.RealTimeBarTick?) {}
    override fun headTimestampProtoBuf(headTimestampProto: HeadTimestampProto.HeadTimestamp?) {}
    override fun histogramDataProtoBuf(histogramDataProto: HistogramDataProto.HistogramData?) {}
    override fun historicalTicksProtoBuf(historicalTicksProto: HistoricalTicksProto.HistoricalTicks?) {}
    override fun historicalTicksBidAskProtoBuf(historicalTicksBidAskProto: HistoricalTicksBidAskProto.HistoricalTicksBidAsk?) {}
    override fun historicalTicksLastProtoBuf(historicalTicksLastProto: HistoricalTicksLastProto.HistoricalTicksLast?) {}
    override fun tickByTickDataProtoBuf(tickByTickDataProto: TickByTickDataProto.TickByTickData?) {}
    override fun updateNewsBulletinProtoBuf(newsBulletinProto: NewsBulletinProto.NewsBulletin?) {}
    override fun newsArticleProtoBuf(newsArticleProto: NewsArticleProto.NewsArticle?) {}
    override fun newsProvidersProtoBuf(newsProvidersProto: NewsProvidersProto.NewsProviders?) {}
    override fun historicalNewsProtoBuf(historicalNewsProto: HistoricalNewsProto.HistoricalNews?) {}
    override fun historicalNewsEndProtoBuf(historicalNewsEndProto: HistoricalNewsEndProto.HistoricalNewsEnd?) {}
    override fun wshMetaDataProtoBuf(wshMetaDataProto: WshMetaDataProto.WshMetaData?) {}
    override fun wshEventDataProtoBuf(wshEventDataProto: WshEventDataProto.WshEventData?) {}
    override fun tickNewsProtoBuf(tickNewsProto: TickNewsProto.TickNews?) {}
    override fun scannerParametersProtoBuf(scannerParametersProto: ScannerParametersProto.ScannerParameters?) {}
    override fun scannerDataProtoBuf(scannerDataProto: ScannerDataProto.ScannerData?) {}
    override fun fundamentalsDataProtoBuf(fundamentalsDataProto: FundamentalsDataProto.FundamentalsData?) {}
    override fun pnlProtoBuf(pnlProto: PnLProto.PnL?) {}
    override fun pnlSingleProtoBuf(pnlSingleProto: PnLSingleProto.PnLSingle?) {}
    override fun receiveFAProtoBuf(receiveFAProto: ReceiveFAProto.ReceiveFA?) {}
    override fun replaceFAEndProtoBuf(replaceFAEndProto: ReplaceFAEndProto.ReplaceFAEnd?) {}
    override fun commissionAndFeesReportProtoBuf(commissionAndFeesReportProto: CommissionAndFeesReportProto.CommissionAndFeesReport?) {}
    override fun historicalScheduleProtoBuf(historicalScheduleProto: HistoricalScheduleProto.HistoricalSchedule?) {}
    override fun rerouteMarketDataRequestProtoBuf(rerouteMarketDataRequestProto: RerouteMarketDataRequestProto.RerouteMarketDataRequest?) {}
    override fun rerouteMarketDepthRequestProtoBuf(rerouteMarketDepthRequestProto: RerouteMarketDepthRequestProto.RerouteMarketDepthRequest?) {}
    override fun secDefOptParameterProtoBuf(secDefOptParameterProto: SecDefOptParameterProto.SecDefOptParameter?) {}
    override fun secDefOptParameterEndProtoBuf(secDefOptParameterEndProto: SecDefOptParameterEndProto.SecDefOptParameterEnd?) {}
    override fun softDollarTiersProtoBuf(softDollarTiersProto: SoftDollarTiersProto.SoftDollarTiers?) {}
    override fun familyCodesProtoBuf(familyCodesProto: FamilyCodesProto.FamilyCodes?) {}
    override fun symbolSamplesProtoBuf(symbolSamplesProto: SymbolSamplesProto.SymbolSamples?) {}
    override fun smartComponentsProtoBuf(smartComponentsProto: SmartComponentsProto.SmartComponents?) {}
    override fun marketRuleProtoBuf(marketRuleProto: MarketRuleProto.MarketRule?) {}
    override fun userInfoProtoBuf(userInfoProto: UserInfoProto.UserInfo?) {}
    override fun nextValidIdProtoBuf(nextValidIdProto: NextValidIdProto.NextValidId?) {}
    override fun currentTimeProtoBuf(currentTimeProto: CurrentTimeProto.CurrentTime?) {}
    override fun currentTimeInMillisProtoBuf(currentTimeInMillisProto: CurrentTimeInMillisProto.CurrentTimeInMillis?) {}
    override fun verifyMessageApiProtoBuf(verifyMessageApiProto: VerifyMessageApiProto.VerifyMessageApi?) {}
    override fun verifyCompletedProtoBuf(verifyCompletedProto: VerifyCompletedProto.VerifyCompleted?) {}
    override fun displayGroupListProtoBuf(displayGroupListProto: DisplayGroupListProto.DisplayGroupList?) {}
    override fun displayGroupUpdatedProtoBuf(displayGroupUpdatedProto: DisplayGroupUpdatedProto.DisplayGroupUpdated?) {}
    override fun marketDepthExchangesProtoBuf(marketDepthExchangesProto: MarketDepthExchangesProto.MarketDepthExchanges?) {}
    override fun configResponseProtoBuf(configResponseProto: ConfigResponseProto.ConfigResponse?) {}
    override fun updateConfigResponseProtoBuf(updateConfigResponseProto: UpdateConfigResponseProto.UpdateConfigResponse?) {}
}
