package com.example.myapi.service

import com.example.myapi.dto.friend.FriendDto
import com.example.myapi.model.Friendship
import com.example.myapi.repository.ChatMessageRepository
import com.example.myapi.repository.FriendshipRepository
import com.example.myapi.repository.UserRepository
import org.springframework.stereotype.Service

@Service
class FriendService(
    private val authService: AuthService,
    private val userRepository: UserRepository,
    private val friendshipRepository: FriendshipRepository,
    private val chatMessageRepository: ChatMessageRepository
) {

    /** Return all friends (both directions) for the caller. */
    fun listByToken(token: String): List<FriendDto>? {
        val myPhone = authService.resolvePhoneByToken(token) ?: return null
        val friendships = friendshipRepository.findAllByRequesterPhoneOrReceiverPhone(myPhone, myPhone)
        val friendPhones = friendships.map { fs ->
            if (fs.requesterPhone == myPhone) fs.receiverPhone else fs.requesterPhone
        }.toSet()
        if (friendPhones.isEmpty()) return emptyList()
        return userRepository.findAll()
            .filter { it.phone in friendPhones }
            .map { toDto(myPhone, it) }
    }

    fun listFriendPhonesByPhone(phone: String): Set<String> {
        val friendships = friendshipRepository.findAllByRequesterPhoneOrReceiverPhone(phone, phone)
        return friendships.map { fs ->
            if (fs.requesterPhone == phone) fs.receiverPhone else fs.requesterPhone
        }.toSet()
    }

    /** Search a single user by phone. Returns null when not found or is self. */
    fun searchByPhone(token: String, targetPhone: String): FriendDto? {
        val myPhone = authService.resolvePhoneByToken(token) ?: return null
        if (targetPhone == myPhone) return null
        return userRepository.findByPhone(targetPhone)?.let { toDto(myPhone, it) }
    }

    /**
     * Add a friend relationship (bidirectional de-dup).
     * Returns false if already friends or target user not found.
     */
    fun addFriend(token: String, targetPhone: String): Boolean {
        val myPhone = authService.resolvePhoneByToken(token) ?: return false
        if (targetPhone == myPhone) return false
        userRepository.findByPhone(targetPhone) ?: return false
        if (
            friendshipRepository.existsByRequesterPhoneAndReceiverPhone(myPhone, targetPhone) ||
            friendshipRepository.existsByRequesterPhoneAndReceiverPhone(targetPhone, myPhone)
        ) return false
        friendshipRepository.save(Friendship(requesterPhone = myPhone, receiverPhone = targetPhone))
        return true
    }

    private fun toDto(myPhone: String, user: com.example.myapi.model.User): FriendDto {
        val friendPhone = user.phone
        val latest = chatMessageRepository.findConversationOrderedDesc(myPhone, friendPhone)
            .firstOrNull()
        val unread = chatMessageRepository
            .countVisibleUnreadFromFriend(friendPhone, myPhone)
            .toInt()

        return FriendDto(
            id = friendPhone,
            name = user.nickname ?: defaultNickname(friendPhone),
            avatarUrl = user.avatarUrl ?: "",
            lastMessage = latest?.content ?: "",
            unreadCount = unread,
            lastMessageTime = latest?.createdAt?.toString(),
        )
    }

    private fun defaultNickname(phone: String): String {
        return if (phone.length >= 4) {
            "用户${phone.takeLast(4)}"
        } else {
            "用户"
        }
    }
}
