package com.example.myapi.service

import org.redisson.api.RMapCache
import org.redisson.api.RedissonClient
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.ObjectProvider
import org.springframework.stereotype.Service
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.random.Random

@Service
class SmsService(
    redissonClientProvider: ObjectProvider<RedissonClient>
) {

    private val logger = LoggerFactory.getLogger(SmsService::class.java)
    private val codes = ConcurrentHashMap<String, String>()
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val codeCache: RMapCache<String, String>? = redissonClientProvider.ifAvailable?.getMapCache("auth:sms:code")

    companion object {
        const val CODE_EXPIRE_MINUTES = 5L
    }

    fun sendCode(phone: String): String {
//        val code = Random.nextInt(100000, 999999).toString()
        val code="111111"
        if (codeCache != null) {
            codeCache.fastPut(phone, code, CODE_EXPIRE_MINUTES, TimeUnit.MINUTES)
        } else {
            codes[phone] = code
            // 5 分钟后自动过期
            scheduler.schedule({ codes.remove(phone) }, CODE_EXPIRE_MINUTES, TimeUnit.MINUTES)
        }

        // 实际生产中在此处调用短信服务商 SDK 发送验证码
        logger.info("[SMS] phone={} code={}", phone, code)

        return code
    }

    fun verifyCode(phone: String, code: String): Boolean {
        return if (codeCache != null) {
            codeCache[phone] == code
        } else {
            codes[phone] == code
        }
    }

    fun removeCode(phone: String) {
        if (codeCache != null) {
            codeCache.fastRemove(phone)
        } else {
            codes.remove(phone)
        }
    }
}
