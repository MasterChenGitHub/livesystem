package com.example.myapi.common

data class ApiResponse<T>(
    val code: Int,
    val data: T
)
