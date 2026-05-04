package com.example.myapi.dto.auth.response

data class LoginResponse(
    val phone: String,
    val nickname: String?,
    val avatarUrl: String?,
    val token: String
)
