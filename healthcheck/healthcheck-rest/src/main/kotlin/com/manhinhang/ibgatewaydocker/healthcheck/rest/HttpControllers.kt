package com.manhinhang.ibgatewaydocker.healthcheck.rest
import com.manhinhang.ibgatewaydocker.healthcheck.IBGatewayClient
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*
import kotlinx.coroutines.*

@RestController
@RequestMapping("/")
class HealthcheckApiController() {

    val ibClient = IBGatewayClient()

    @GetMapping("/ready")
    fun ready(): ResponseEntity<Any> {
        return ResponseEntity.status(HttpStatus.OK).body("OK");
    }

    @GetMapping("/healthcheck")
    fun healthcheck(): ResponseEntity<Any> {
        val result = runBlocking { ibClient.ping() }
        if (result.isSuccess) {
            return ResponseEntity.status(HttpStatus.OK).body("OK")
        }
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body("Fail")
    }
}