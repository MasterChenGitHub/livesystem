package com.example.myapi.dto.auth.request

data class RegisterRequest(
    val phone: String,
    val verificationCode: String
)
