package com.example.webrtcserver

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class WebrtcServerApplication

fun main(args: Array<String>) {
    runApplication<WebrtcServerApplication>(*args)
}
