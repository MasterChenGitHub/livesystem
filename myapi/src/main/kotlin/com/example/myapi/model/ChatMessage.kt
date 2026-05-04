package com.example.myapi.model

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.LocalDateTime

@Entity
@Table(name = "chat_message")
class ChatMessage(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long? = null,

    @Column(name = "sender_phone", nullable = false, length = 20)
    var senderPhone: String,

    @Column(name = "receiver_phone", nullable = false, length = 20)
    var receiverPhone: String,

    @Column(nullable = false, columnDefinition = "TEXT")
    var content: String,

    @Column(nullable = false, length = 20)
    var type: String = "text", // text, image, voice

    @Column(name = "is_read", nullable = false)
    var read: Boolean = false,

    @Column(name = "deleted_by_sender", nullable = false)
    var deletedBySender: Boolean = false,

    @Column(name = "deleted_by_receiver", nullable = false)
    var deletedByReceiver: Boolean = false,

    @Column
    var readAt: LocalDateTime? = null,

    @Column(nullable = false)
    var createdAt: LocalDateTime = LocalDateTime.now(),

    @Column(length = 500)
    var imageUrl: String? = null,

    @Column(length = 500)
    var thumbUrl: String? = null,

    @Column
    var imageWidth: Int? = null,

    @Column
    var imageHeight: Int? = null,

    @Column
    var imageSize: Long? = null,

    // Video fields
    @Column(length = 500)
    var videoUrl: String? = null,

    @Column(length = 500)
    var videoThumbUrl: String? = null,

    @Column
    var videoDuration: Int? = null, // milliseconds

    @Column
    var videoWidth: Int? = null,

    @Column
    var videoHeight: Int? = null,

    // Voice fields
    @Column(length = 500)
    var voiceUrl: String? = null,

    @Column
    var voiceDuration: Int? = null, // seconds
)
