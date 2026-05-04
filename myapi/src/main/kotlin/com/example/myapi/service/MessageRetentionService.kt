package com.example.myapi.service

import com.example.myapi.repository.ChatMessageRepository
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.LocalDateTime

@Service
class MessageRetentionService(
    private val chatMessageRepository: ChatMessageRepository,
    @Value("\${message.retention.read-days:1}")
    private val readRetentionDays: Long,
    @Value("\${message.retention.unread-media-days:3}")
    private val unreadMediaRetentionDays: Long,
    @Value("\${message.retention.unread-nonmedia-max-days:90}")
    private val unreadNonMediaMaxDays: Long,
) {
    private val logger = LoggerFactory.getLogger(MessageRetentionService::class.java)

    private val mediaTypes = listOf("image", "video")

    @Transactional
    @Scheduled(cron = "\${message.retention.cleanup-cron:0 15 4 * * *}")
    fun cleanupExpiredMessages() {
        val now = LocalDateTime.now()

        val readCutoff = now.minusDays(readRetentionDays)
        val unreadMediaCutoff = now.minusDays(unreadMediaRetentionDays)
        val unreadNonMediaCutoff = now.minusDays(unreadNonMediaMaxDays)

        val deletedRead = chatMessageRepository.deleteReadMessagesBefore(readCutoff)
        val deletedUnreadMedia = chatMessageRepository.deleteUnreadByTypesBefore(
            types = mediaTypes,
            cutoff = unreadMediaCutoff,
        )
        val deletedUnreadNonMedia = chatMessageRepository.deleteUnreadNonMediaBefore(
            excludedTypes = mediaTypes,
            cutoff = unreadNonMediaCutoff,
        )

        if (deletedRead > 0 || deletedUnreadMedia > 0 || deletedUnreadNonMedia > 0) {
            logger.info(
                "Message retention cleanup finished: read={}, unreadMedia={}, unreadNonMedia={}",
                deletedRead,
                deletedUnreadMedia,
                deletedUnreadNonMedia,
            )
        }
    }
}
