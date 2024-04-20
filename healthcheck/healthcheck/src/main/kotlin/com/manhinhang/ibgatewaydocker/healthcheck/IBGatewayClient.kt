package com.manhinhang.ibgatewaydocker.healthcheck

import com.ib.client.EClientSocket
import com.ib.client.EJavaSignal
import kotlinx.coroutines.*

class IBGatewayClient {
    val client: EClientSocket
    companion object {
        val clientId = (System.getenv("HEALTHCHECK_CLIENT_ID")?.toIntOrNull() ?: 999)
        val port = (System.getenv("IB_GATEWAY_INTERNAL_PORT")?.toIntOrNull() ?: 4001)
        val host = "localhost"
    }

    init {
        client = createIBClient()
    }

    private fun createIBClient(): EClientSocket {
        val signal = EJavaSignal();
        val client = EClientSocket(Wrapper(), signal)
        return client
    }

    suspend fun connect():Boolean = withContext(Dispatchers.IO) {
        if (!client.isConnected) {
            val client = createIBClient()
            client.eConnect(host, port, clientId)
        }
        client.isConnected
    }

    fun disconnect() {
        client.eDisconnect()
    }

    suspend fun ping():Result<Any> = coroutineScope {
        runCatching {
            val isConnected = connect()
            if (isConnected) {
                println("Ping IB Gateway successful")
                client.eDisconnect()
            }else {
                throw InterruptedException("Can not connect to IB Gateway")
            }
        }
    }

}