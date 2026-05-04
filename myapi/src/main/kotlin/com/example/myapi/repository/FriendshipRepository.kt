package com.example.myapi.repository

import com.example.myapi.model.Friendship
import org.springframework.data.jpa.repository.JpaRepository

interface FriendshipRepository : JpaRepository<Friendship, Long> {
    fun existsByRequesterPhoneAndReceiverPhone(requesterPhone: String, receiverPhone: String): Boolean
    fun findAllByRequesterPhoneOrReceiverPhone(requesterPhone: String, receiverPhone: String): List<Friendship>
}
