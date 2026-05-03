package com.manhinhang.ibgatewaydocker.healthcheck.rest

import com.manhinhang.ibgatewaydocker.healthcheck.IBGatewayClient
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/")
class HealthcheckApiController {

    private val ibClient = IBGatewayClient()

    // EClientSocket is not documented as thread-safe and we share one
    // ibClient across Tomcat worker threads. Serialise pings to avoid
    // corrupting the socket's internal state under concurrent load.
    private val pingLock = Mutex()

    @GetMapping("/ready")
    fun ready(): ResponseEntity<String> =
        ResponseEntity.status(HttpStatus.OK).body("OK")

    @GetMapping("/healthcheck")
    fun healthcheck(): ResponseEntity<String> {
        val result = runBlocking { pingLock.withLock { ibClient.ping() } }
        return if (result.isSuccess) {
            ResponseEntity.status(HttpStatus.OK).body("OK")
        } else {
            ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(result.exceptionOrNull()?.message ?: "Fail")
        }
    }
}
