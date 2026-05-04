package com.example.myapi.service

import com.example.myapi.model.ChatMessage
import com.example.myapi.repository.ChatMessageRepository
import org.springframework.stereotype.Service
import java.time.LocalDateTime

@Service
class MessageService(
    private val messageRepository: ChatMessageRepository
) {
    
    /**
     * Save a text message between two users
     */
    fun sendMessage(
        senderPhone: String,
        receiverPhone: String,
        content: String,
        type: String = "text",
        imageUrl: String? = null,
        thumbUrl: String? = null,
        imageWidth: Int? = null,
        imageHeight: Int? = null,
        imageSize: Long? = null,
        videoUrl: String? = null,
        videoThumbUrl: String? = null,
        videoDuration: Int? = null,
        videoWidth: Int? = null,
        videoHeight: Int? = null,
        voiceUrl: String? = null,
        voiceDuration: Int? = null,
    ): ChatMessage {
        val message = ChatMessage(
            senderPhone = senderPhone,
            receiverPhone = receiverPhone,
            content = content,
            type = type,
            read = false,
            imageUrl = imageUrl,
            thumbUrl = thumbUrl,
            imageWidth = imageWidth,
            imageHeight = imageHeight,
            imageSize = imageSize,
            videoUrl = videoUrl,
            videoThumbUrl = videoThumbUrl,
            videoDuration = videoDuration,
            videoWidth = videoWidth,
            videoHeight = videoHeight,
            voiceUrl = voiceUrl,
            voiceDuration = voiceDuration,
            createdAt = LocalDateTime.now()
        )
        return messageRepository.save(message)
    }
    
    /**
     * Get all messages in a conversation between two users, sorted by creation time
     */
    fun getConversation(myPhone: String, friendPhone: String): List<ChatMessage> {
        return messageRepository.findConversation(myPhone, friendPhone).reversed()
    }
    
    /**
     * Get the last N messages in a conversation
     */
    fun getConversationLimited(myPhone: String, friendPhone: String, limit: Int): List<ChatMessage> {
        return messageRepository.findConversation(myPhone, friendPhone, limit).reversed()
    }

    fun markConversationRead(myPhone: String, friendPhone: String): Int {
        return messageRepository.markConversationRead(friendPhone = friendPhone, myPhone = myPhone)
    }

    fun deleteConversationMessagesByIds(
        myPhone: String,
        friendPhone: String,
        messageIds: Collection<Long>,
    ): Int {
        if (messageIds.isEmpty()) return 0
        val deletedAsSender = messageRepository.markConversationMessagesDeletedBySender(
            myPhone = myPhone,
            friendPhone = friendPhone,
            messageIds = messageIds,
        )
        val deletedAsReceiver = messageRepository.markConversationMessagesDeletedByReceiver(
            myPhone = myPhone,
            friendPhone = friendPhone,
            messageIds = messageIds,
        )
        return deletedAsSender + deletedAsReceiver
    }
}
