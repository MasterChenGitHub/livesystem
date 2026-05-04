package com.example.webrtcserver.signaling.ws

import com.example.webrtcserver.signaling.service.SignalingService
import java.io.EOFException
import java.io.IOException
import java.nio.channels.ClosedChannelException
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component
import org.springframework.web.socket.CloseStatus
import org.springframework.web.socket.TextMessage
import org.springframework.web.socket.WebSocketSession
import org.springframework.web.socket.handler.TextWebSocketHandler

@Component
class SignalingWebSocketHandler(
    private val signalingService: SignalingService
) : TextWebSocketHandler() {

    private val logger = LoggerFactory.getLogger(SignalingWebSocketHandler::class.java)
    private val USER_ID_KEY = "userId"

    override fun afterConnectionEstablished(session: WebSocketSession) {
        val token = getTokenFromUri(session) ?: run {
            closeWithReason(session, "token required")
            return
        }
        val userId = getUserIdFromUri(session)?.takeIf { it.isNotBlank() } ?: token
        session.attributes[USER_ID_KEY] = userId
        signalingService.register(userId, session)
    }

    override fun handleTextMessage(session: WebSocketSession, message: TextMessage) {
        val userId = session.attributes[USER_ID_KEY] as? String
        if (userId.isNullOrBlank()) {
            closeWithReason(session, "unauthorized")
            return
        }

        signalingService.handleIncoming(userId, message.payload)
    }

    override fun afterConnectionClosed(session: WebSocketSession, status: CloseStatus) {
        signalingService.unregister(session)
    }

    override fun handleTransportError(session: WebSocketSession, exception: Throwable) {
        val expectedDisconnect =
            exception is EOFException ||
            exception is ClosedChannelException ||
            (exception is IOException && exception.cause is ClosedChannelException) ||
            (exception.message?.contains("ClosedChannelException") == true)

        if (expectedDisconnect) {
            logger.info("Signaling client disconnected: {}", session.id)
        } else {
            logger.warn("Signaling transport error: {}", session.id, exception)
        }
    }

    private fun getTokenFromUri(session: WebSocketSession): String? =
        getQueryParam(session, "token")

    private fun getUserIdFromUri(session: WebSocketSession): String? =
        getQueryParam(session, "userId")

    private fun getQueryParam(session: WebSocketSession, name: String): String? {
        val uri = session.uri ?: return null
        val query = uri.query ?: return null
        return query.split("&")
            .map { it.split("=") }
            .firstOrNull { it.size == 2 && it[0] == name }
            ?.get(1)
            ?.takeIf { it.isNotBlank() }
    }

    private fun closeWithReason(session: WebSocketSession, reason: String) {
        try {
            session.close(CloseStatus(4000, reason))
        } catch (ex: Exception) {
            logger.warn("Failed to close session {}: {}", session.id, ex.message)
        }
    }
}
