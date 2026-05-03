package com.manhinhang.ibgatewaydocker.healthcheck

import com.ib.client.EClientSocket
import com.ib.client.EJavaSignal
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

class IBGatewayClient {
    private val wrapper = Wrapper()
    private val client: EClientSocket = createIBClient(wrapper)

    companion object {
        val clientId = System.getenv("HEALTHCHECK_CLIENT_ID")?.toIntOrNull() ?: 999
        val port = System.getenv("IB_GATEWAY_INTERNAL_PORT")?.toIntOrNull()
            ?: System.getenv("IBGW_PORT")?.toIntOrNull()
            ?: 4002
        const val HOST = "localhost"

        // How long to give the gateway to surface a real error after the TCP
        // socket comes up. eConnect returns immediately on socket success;
        // auth/permission errors arrive on a callback shortly after.
        const val ERROR_SETTLE_MILLIS = 500L
    }

    private fun createIBClient(wrapper: Wrapper): EClientSocket {
        val signal = EJavaSignal()
        return EClientSocket(wrapper, signal)
    }

    private suspend fun connect(): Boolean = withContext(Dispatchers.IO) {
        if (!client.isConnected) {
            wrapper.lastError = null
            client.eConnect(HOST, port, clientId)
        }
        client.isConnected
    }

    private fun disconnect() {
        client.eDisconnect()
    }

    suspend fun ping(): Result<Any> = coroutineScope {
        runCatching {
            val isConnected = connect()
            if (!isConnected) {
                throw InterruptedException("Can not connect to IB Gateway")
            }
            // Give the gateway a brief window to report errors via callbacks
            // (auth failure, API not enabled, etc.) before declaring success.
            delay(ERROR_SETTLE_MILLIS)
            val err = wrapper.lastError
            disconnect()
            if (err != null) {
                throw IllegalStateException("IB Gateway reported error: $err")
            }
            println("Ping IB Gateway successful")
        }
    }
}
