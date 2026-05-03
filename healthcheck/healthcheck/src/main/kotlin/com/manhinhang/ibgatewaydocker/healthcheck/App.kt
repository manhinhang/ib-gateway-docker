package com.manhinhang.ibgatewaydocker.healthcheck

import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val client = IBGatewayClient()
    val result = client.ping()
    result.exceptionOrNull()?.let { throw it }
    return@runBlocking
}
