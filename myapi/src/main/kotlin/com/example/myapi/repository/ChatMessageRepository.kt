package com.example.myapi.repository

import com.example.myapi.model.ChatMessage
import jakarta.transaction.Transactional
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.time.LocalDateTime

interface ChatMessageRepository : JpaRepository<ChatMessage, Long> {
    @Query(
        """
        SELECT m FROM ChatMessage m 
        WHERE (m.senderPhone = :myPhone AND m.receiverPhone = :friendPhone AND m.deletedBySender = false)
           OR (m.senderPhone = :friendPhone AND m.receiverPhone = :myPhone AND m.deletedByReceiver = false)
        ORDER BY m.createdAt DESC
        """
    )
    fun findConversation(
        @Param("myPhone") myPhone: String,
        @Param("friendPhone") friendPhone: String,
    ): List<ChatMessage>

    @Query(
        """
        SELECT m FROM ChatMessage m 
        WHERE (m.senderPhone = :myPhone AND m.receiverPhone = :friendPhone AND m.deletedBySender = false)
           OR (m.senderPhone = :friendPhone AND m.receiverPhone = :myPhone AND m.deletedByReceiver = false)
        ORDER BY m.createdAt DESC
        LIMIT :limit
        """
    )
    fun findConversation(
        @Param("myPhone") myPhone: String,
        @Param("friendPhone") friendPhone: String,
        @Param("limit") limit: Int,
    ): List<ChatMessage>

    @Query(
        """
        SELECT m FROM ChatMessage m
        WHERE (m.senderPhone = :myPhone AND m.receiverPhone = :friendPhone AND m.deletedBySender = false)
           OR (m.senderPhone = :friendPhone AND m.receiverPhone = :myPhone AND m.deletedByReceiver = false)
        ORDER BY m.createdAt DESC
        """
    )
    fun findConversationOrderedDesc(
        @Param("myPhone") myPhone: String,
        @Param("friendPhone") friendPhone: String,
    ): List<ChatMessage>

    fun countBySenderPhoneAndReceiverPhoneAndReadFalse(senderPhone: String, receiverPhone: String): Long

    @Query(
        """
        SELECT COUNT(m) FROM ChatMessage m
        WHERE m.senderPhone = :friendPhone
          AND m.receiverPhone = :myPhone
          AND m.read = false
          AND m.deletedByReceiver = false
        """
    )
    fun countVisibleUnreadFromFriend(
        @Param("friendPhone") friendPhone: String,
        @Param("myPhone") myPhone: String,
    ): Long

    @Transactional
    @Modifying
    @Query(
        """
        UPDATE ChatMessage m
                SET m.read = true,
                        m.readAt = CURRENT_TIMESTAMP
        WHERE m.senderPhone = :friendPhone
          AND m.receiverPhone = :myPhone
          AND m.read = false
        """
    )
    fun markConversationRead(
        @Param("friendPhone") friendPhone: String,
        @Param("myPhone") myPhone: String
    ): Int

        @Transactional
        @Modifying
        @Query(
                """
                UPDATE ChatMessage m
                SET m.deletedBySender = true
                WHERE m.id IN :messageIds
                    AND m.senderPhone = :myPhone
                    AND m.receiverPhone = :friendPhone
                """
        )
        fun markConversationMessagesDeletedBySender(
                @Param("myPhone") myPhone: String,
                @Param("friendPhone") friendPhone: String,
                @Param("messageIds") messageIds: Collection<Long>,
        ): Int

        @Transactional
        @Modifying
        @Query(
                """
                UPDATE ChatMessage m
                SET m.deletedByReceiver = true
                WHERE m.id IN :messageIds
                    AND m.senderPhone = :friendPhone
                    AND m.receiverPhone = :myPhone
                """
        )
        fun markConversationMessagesDeletedByReceiver(
                @Param("myPhone") myPhone: String,
                @Param("friendPhone") friendPhone: String,
                @Param("messageIds") messageIds: Collection<Long>,
        ): Int

    @Transactional
    @Modifying
    @Query(
        """
        DELETE FROM ChatMessage m
        WHERE m.read = true
          AND m.readAt IS NOT NULL
          AND m.readAt <= :cutoff
        """
    )
    fun deleteReadMessagesBefore(@Param("cutoff") cutoff: LocalDateTime): Int

    @Transactional
    @Modifying
    @Query(
        """
        DELETE FROM ChatMessage m
        WHERE m.read = false
          AND m.type IN :types
          AND m.createdAt <= :cutoff
        """
    )
    fun deleteUnreadByTypesBefore(
        @Param("types") types: Collection<String>,
        @Param("cutoff") cutoff: LocalDateTime,
    ): Int

    @Transactional
    @Modifying
    @Query(
        """
        DELETE FROM ChatMessage m
        WHERE m.read = false
          AND m.type NOT IN :excludedTypes
          AND m.createdAt <= :cutoff
        """
    )
    fun deleteUnreadNonMediaBefore(
        @Param("excludedTypes") excludedTypes: Collection<String>,
        @Param("cutoff") cutoff: LocalDateTime,
    ): Int
}
