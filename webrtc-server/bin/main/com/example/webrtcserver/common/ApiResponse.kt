package com.example.webrtcserver.common

data class ApiResponse<T>(
    val code: Int,
    val data: T
)
