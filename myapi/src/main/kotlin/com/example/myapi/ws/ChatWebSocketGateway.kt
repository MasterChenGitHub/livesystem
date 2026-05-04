package com.example.myapi.ws

import com.example.myapi.model.ChatMessage
import org.springframework.stereotype.Component
import org.springframework.web.socket.TextMessage
import org.springframework.web.socket.WebSocketSession
import tools.jackson.module.kotlin.jacksonObjectMapper
import java.util.concurrent.ConcurrentHashMap

@Component
class ChatWebSocketGateway {
    private val objectMapper = jacksonObjectMapper()
    private val sessionsByPhone = ConcurrentHashMap<String, MutableSet<WebSocketSession>>()

    fun isOnline(phone: String): Boolean = sessionsByPhone[phone]?.any { it.isOpen } == true

    fun register(phone: String, session: WebSocketSession) {
        sessionsByPhone.compute(phone) { _, existing ->
            (existing ?: ConcurrentHashMap.newKeySet()).apply { add(session) }
        }
    }

    fun unregister(phone: String, session: WebSocketSession) {
        sessionsByPhone.computeIfPresent(phone) { _, existing ->
            existing.remove(session)
            if (existing.isEmpty()) null else existing
        }
    }

    fun pushChatMessage(receiverPhone: String, message: ChatMessage) {
        val payload = mapOf(
            "type" to "chat-message",
            "data" to mapOf(
                "id" to message.id,
                "senderPhone" to message.senderPhone,
                "receiverPhone" to message.receiverPhone,
                "content" to message.content,
                "type" to message.type,
                "read" to message.read,
                "createdAt" to message.createdAt.toString(),
                "imageUrl" to message.imageUrl,
                "thumbUrl" to message.thumbUrl,
                "imageWidth" to message.imageWidth,
                "imageHeight" to message.imageHeight,
                "imageSize" to message.imageSize,
                "videoUrl" to message.videoUrl,
                "videoThumbUrl" to message.videoThumbUrl,
                "videoDuration" to message.videoDuration,
                "videoWidth" to message.videoWidth,
                "videoHeight" to message.videoHeight,
            )
        )

        pushToPhone(receiverPhone, payload)
    }

    fun pushPresence(toPhone: String, userId: String, online: Boolean) {
        pushToPhone(
            toPhone,
            mapOf(
                "type" to "presence",
                "data" to mapOf(
                    "userId" to userId,
                    "online" to online,
                )
            )
        )
    }

    fun pushTyping(toPhone: String, fromUserId: String, isTyping: Boolean) {
        pushToPhone(
            toPhone,
            mapOf(
                "type" to "typing",
                "data" to mapOf(
                    "fromUserId" to fromUserId,
                    "isTyping" to isTyping,
                )
            )
        )
    }

    fun pushReadReceipt(toPhone: String, readerId: String) {
        pushToPhone(
            toPhone,
            mapOf(
                "type" to "chat-read",
                "data" to mapOf(
                    "readerId" to readerId,
                )
            )
        )
    }

    private fun pushToPhone(phone: String, payload: Map<String, Any?>) {
        val sessions = sessionsByPhone[phone] ?: return
        if (sessions.isEmpty()) return

        val text = objectMapper.writeValueAsString(payload)
        val wsMessage = TextMessage(text)

        sessions.forEach { session ->
            if (!session.isOpen) return@forEach
            try {
                synchronized(session) {
                    session.sendMessage(wsMessage)
                }
            } catch (_: Exception) {
                // Ignore broken sessions; closed sessions are cleaned up by lifecycle callbacks.
            }
        }
    }
}
