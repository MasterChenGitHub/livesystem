package com.example.myapi.controller

import com.example.myapi.common.ApiResponse
import com.example.myapi.dto.auth.request.LoginRequest
import com.example.myapi.dto.auth.request.LogoutRequest
import com.example.myapi.dto.auth.request.SendCodeRequest
import com.example.myapi.dto.auth.request.UpdateAvatarRequest
import com.example.myapi.dto.auth.request.UpdateNicknameRequest
import com.example.myapi.dto.auth.response.LoginResponse
import com.example.myapi.dto.auth.response.MessageResponse
import com.example.myapi.service.AuthService
import com.example.myapi.service.SmsService
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.bind.annotation.RequestHeader

@RestController
@RequestMapping("/api/auth")
class AuthController(
    private val authService: AuthService,
    private val smsService: SmsService
) {

    private val phoneRegex = Regex("^1\\d{10}$")
    private val verificationCodeRegex = Regex("^\\d{4,6}$")

    @PostMapping("/getCode")
    fun sendCode(@RequestBody request: SendCodeRequest): ResponseEntity<ApiResponse<MessageResponse>> {
        val phone = request.phone.trim()
        if (!phoneRegex.matches(phone)) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse(code = 400, data = MessageResponse("invalid phone format")))
        }
        smsService.sendCode(phone)
        return ResponseEntity.ok(ApiResponse(code = 200, data = MessageResponse("verification code sent")))
    }

    @PostMapping("/login")
    fun login(@RequestBody request: LoginRequest): ResponseEntity<ApiResponse<Any>> {
        if (request.phone.isBlank() || request.verificationCode.isBlank()) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse(code = 400, data = MessageResponse("phone or verificationCode cannot be empty")))
        }

        val phone = request.phone.trim()
        val verificationCode = request.verificationCode.trim()
        if (!phoneRegex.matches(phone)) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse(code = 400, data = MessageResponse("invalid phone format")))
        }

        if (!verificationCodeRegex.matches(verificationCode)) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse(code = 400, data = MessageResponse("invalid verificationCode format")))
        }

        val loginResponse = authService.loginOrRegister(phone, verificationCode)
            ?: return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(ApiResponse(code = 401, data = MessageResponse("invalid verificationCode")))

        return ResponseEntity.ok(
            ApiResponse(
                code = 200,
                data = loginResponse
            )
        )
    }

    @PostMapping("/logout")
    fun logout(@RequestBody request: LogoutRequest): ResponseEntity<ApiResponse<MessageResponse>> {
        if (request.token.isBlank()) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse(code = 400, data = MessageResponse("token cannot be empty")))
        }

        val success = authService.logout(request.token.trim())
        if (!success) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(ApiResponse(code = 401, data = MessageResponse("invalid token")))
        }

        return ResponseEntity.ok(ApiResponse(code = 200, data = MessageResponse("logout success")))
    }

    @PostMapping("/profile/avatar")
    fun updateAvatar(
        @RequestHeader("Authorization") authHeader: String,
        @RequestBody request: UpdateAvatarRequest
    ): ResponseEntity<ApiResponse<Any>> {
        val avatarUrl = request.avatarUrl.trim()
        if (avatarUrl.isBlank()) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse(code = 400, data = MessageResponse("avatarUrl cannot be empty")))
        }

        val token = authHeader.removePrefix("Bearer ").trim()
        val updatedAvatar = authService.updateAvatar(token, avatarUrl)
            ?: return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(ApiResponse(code = 401, data = MessageResponse("invalid token")))

        return ResponseEntity.ok(
            ApiResponse(
                code = 200,
                data = mapOf("avatarUrl" to updatedAvatar)
            )
        )
    }

    @PostMapping("/profile/nickname")
    fun updateNickname(
        @RequestHeader("Authorization") authHeader: String,
        @RequestBody request: UpdateNicknameRequest
    ): ResponseEntity<ApiResponse<Any>> {
        val nickname = request.nickname.trim()
        if (nickname.isBlank()) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse(code = 400, data = MessageResponse("nickname cannot be empty")))
        }
        if (nickname.length > 20) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse(code = 400, data = MessageResponse("nickname too long")))
        }

        val token = authHeader.removePrefix("Bearer ").trim()
        val updatedNickname = authService.updateNickname(token, nickname)
            ?: return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(ApiResponse(code = 401, data = MessageResponse("invalid token")))

        return ResponseEntity.ok(
            ApiResponse(
                code = 200,
                data = mapOf("nickname" to updatedNickname)
            )
        )
    }
}
