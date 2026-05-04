package com.example.myapi.dto.friend

data class FriendDto(
    val id: String,
    val name: String,
    val avatarUrl: String,
    val lastMessage: String = "",
    val unreadCount: Int = 0,
    val lastMessageTime: String? = null
)
