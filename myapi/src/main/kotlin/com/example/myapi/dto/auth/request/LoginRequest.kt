package com.example.myapi.dto.auth.request

data class LoginRequest(
    val phone: String,
    val verificationCode: String
)
