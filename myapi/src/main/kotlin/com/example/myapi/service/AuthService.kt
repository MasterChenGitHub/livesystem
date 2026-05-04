package com.example.myapi.service

import com.example.myapi.dto.auth.response.LoginResponse
import com.example.myapi.model.User
import com.example.myapi.repository.UserRepository
import org.redisson.api.RMapCache
import org.redisson.api.RedissonClient
import org.springframework.beans.factory.ObjectProvider
import org.springframework.stereotype.Service
import java.util.UUID
import java.util.concurrent.TimeUnit

@Service
class AuthService(
    private val smsService: SmsService,
    private val userRepository: UserRepository,
    redissonClientProvider: ObjectProvider<RedissonClient>
) {

    companion object {
        private const val SESSION_EXPIRE_DAYS = 7L
    }

    private val sessions = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val sessionCache: RMapCache<String, String>? = redissonClientProvider.ifAvailable?.getMapCache("auth:session")

    fun loginOrRegister(phone: String, verificationCode: String): LoginResponse? {
        if (!smsService.verifyCode(phone, verificationCode)) {
            return null
        }
        smsService.removeCode(phone)

        val user = userRepository.findByPhone(phone)
            ?: userRepository.save(
                User(
                    phone = phone,
                    nickname = defaultNickname(phone),
                    avatarUrl = null
                )
            )

        val token = UUID.randomUUID().toString()
        if (sessionCache != null) {
            sessionCache.fastPut(token, phone, SESSION_EXPIRE_DAYS, TimeUnit.DAYS)
        } else {
            sessions[token] = phone
        }
        return LoginResponse(
            phone = user.phone,
            nickname = user.nickname,
            avatarUrl = user.avatarUrl,
            token = token
        )
    }

    private fun defaultNickname(phone: String): String {
        return "用户${phone.takeLast(4)}"
    }

    fun logout(token: String): Boolean {
        return if (sessionCache != null) {
            sessionCache.fastRemove(token) > 0
        } else {
            sessions.remove(token) != null
        }
    }

    fun resolvePhoneByToken(token: String): String? {
        return if (sessionCache != null) {
            sessionCache[token]
        } else {
            sessions[token]
        }
    }

    fun updateAvatar(token: String, avatarUrl: String): String? {
        val phone = resolvePhoneByToken(token) ?: return null
        val user = userRepository.findByPhone(phone) ?: return null
        user.avatarUrl = avatarUrl
        return userRepository.save(user).avatarUrl
    }

    fun updateNickname(token: String, nickname: String): String? {
        val phone = resolvePhoneByToken(token) ?: return null
        val user = userRepository.findByPhone(phone) ?: return null
        user.nickname = nickname
        return userRepository.save(user).nickname
    }
}
