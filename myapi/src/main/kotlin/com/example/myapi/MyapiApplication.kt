package com.example.myapi

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication
import org.springframework.scheduling.annotation.EnableScheduling

@SpringBootApplication
@EnableScheduling
class MyapiApplication

fun main(args: Array<String>) {
    runApplication<MyapiApplication>(*args)
}
