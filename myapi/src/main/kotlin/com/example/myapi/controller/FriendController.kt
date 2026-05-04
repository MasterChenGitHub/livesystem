package com.example.myapi.controller

import com.example.myapi.common.ApiResponse
import com.example.myapi.dto.auth.response.MessageResponse
import com.example.myapi.dto.friend.FriendDto
import com.example.myapi.service.FriendService
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

data class AddFriendRequest(val phone: String = "")

private sealed class AuthResult {
    data class Success(val token: String) : AuthResult()
    data class Error(val response: ResponseEntity<ApiResponse<MessageResponse>>) : AuthResult()
}

@RestController
@RequestMapping("/api/friends")
class FriendController(
    private val friendService: FriendService
) {

    private fun resolveToken(authHeader: String?): String? =
        authHeader?.removePrefix("Bearer ")?.trim()?.takeIf { it.isNotBlank() }

    private fun validateToken(authHeader: String?): AuthResult {
        val token = resolveToken(authHeader)
        return if (token != null) {
            AuthResult.Success(token)
        } else {
            AuthResult.Error(
                ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(ApiResponse(code = 401, data = MessageResponse("token is required")))
            )
        }
    }

    @GetMapping("/list")
    fun list(
        @RequestHeader("Authorization", required = false) authHeader: String?
    ): ResponseEntity<ApiResponse<Any>> =
        when (val auth = validateToken(authHeader)) {
            is AuthResult.Error -> auth.response as ResponseEntity<ApiResponse<Any>>
            is AuthResult.Success -> {
                val friends = friendService.listByToken(auth.token)
                    ?: return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(ApiResponse(code = 401, data = MessageResponse("invalid token")))
                ResponseEntity.ok(ApiResponse(code = 200, data = friends))
            }
        }

    @GetMapping("/search")
    fun search(
        @RequestHeader("Authorization", required = false) authHeader: String?,
        @RequestParam phone: String
    ): ResponseEntity<ApiResponse<Any>> =
        when (val auth = validateToken(authHeader)) {
            is AuthResult.Error -> auth.response as ResponseEntity<ApiResponse<Any>>
            is AuthResult.Success -> {
                val found = friendService.searchByPhone(auth.token, phone.trim())
                    ?: return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(ApiResponse(code = 404, data = MessageResponse("user not found")))
                ResponseEntity.ok(ApiResponse(code = 200, data = found))
            }
        }

    @PostMapping("/add")
    fun add(
        @RequestHeader("Authorization", required = false) authHeader: String?,
        @RequestBody request: AddFriendRequest
    ): ResponseEntity<ApiResponse<MessageResponse>> {
        return when (val auth = validateToken(authHeader)) {
            is AuthResult.Error -> auth.response
            is AuthResult.Success -> {
                if (request.phone.isBlank()) {
                    ResponseEntity.badRequest()
                        .body(ApiResponse(code = 400, data = MessageResponse("phone is required")))
                } else {
                    val success = friendService.addFriend(auth.token, request.phone.trim())
                    if (success) {
                        ResponseEntity.ok(ApiResponse(code = 200, data = MessageResponse("added")))
                    } else {
                        ResponseEntity.status(HttpStatus.CONFLICT)
                            .body(ApiResponse(code = 409, data = MessageResponse("already friends or user not found")))
                    }
                }
            }
        }
    }}