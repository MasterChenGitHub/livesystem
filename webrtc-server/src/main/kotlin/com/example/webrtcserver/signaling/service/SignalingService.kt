package com.example.webrtcserver.signaling.service

import com.example.webrtcserver.signaling.model.SignalMessage
import tools.jackson.databind.ObjectMapper
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.web.socket.CloseStatus
import org.springframework.web.socket.TextMessage
import org.springframework.web.socket.WebSocketSession
import java.util.concurrent.ConcurrentHashMap

@Service
class SignalingService(
    private val objectMapper: ObjectMapper
) {

    private val logger = LoggerFactory.getLogger(SignalingService::class.java)

    private data class ClientContext(
        val userId: String
    )

    private val userSessions = ConcurrentHashMap<String, MutableSet<WebSocketSession>>()
    private val sessionContexts = ConcurrentHashMap<String, ClientContext>()
    private val userRooms = ConcurrentHashMap<String, String?>()
    private val roomMembers = ConcurrentHashMap<String, MutableSet<String>>()
    private val sessionLocks = ConcurrentHashMap<String, Any>()

    fun register(userId: String, session: WebSocketSession) {
        val sessions = userSessions.computeIfAbsent(userId) { ConcurrentHashMap.newKeySet() }
        sessions.add(session)
        sessionContexts[session.id] = ClientContext(userId = userId)

        sendToSession(
            session,
            SignalMessage(
                type = "connected",
                from = "server"
            )
        )
    }

    fun unregister(session: WebSocketSession) {
        val context = sessionContexts.remove(session.id) ?: return
        sessionLocks.remove(session.id)
        val sessions = userSessions[context.userId]
        sessions?.remove(session)
        if (sessions.isNullOrEmpty()) {
            userSessions.remove(context.userId)
            leaveRoom(context.userId, userRooms[context.userId], notify = true)
        }
    }

    fun handleIncoming(userId: String, rawText: String) {
        val incoming = try {
            objectMapper.readValue(rawText, SignalMessage::class.java)
        } catch (ex: Exception) {
            logger.warn("Invalid signaling payload from {}: {}", userId, rawText)
            sendToUser(
                userId,
                SignalMessage(
                    type = "error",
                    from = "server",
                    reason = "invalid payload"
                )
            )
            return
        }

        when (incoming.type.lowercase()) {
            "join" -> handleJoin(userId, incoming.roomId)
            "leave" -> {
                leaveRoom(userId, userRooms[userId], notify = true)
            }
            "offer", "answer", "ice-candidate", "hangup" -> forwardPeerMessage(userId, incoming)
            "ping" -> sendToUser(userId, SignalMessage(type = "pong", from = "server"))
            else -> sendToUser(
                userId,
                SignalMessage(type = "error", from = "server", reason = "unsupported type: ${incoming.type}")
            )
        }
    }

    private fun handleJoin(userId: String, roomId: String?) {
        if (roomId.isNullOrBlank()) {
            sendToUser(
                userId,
                SignalMessage(type = "error", from = "server", reason = "roomId is required")
            )
            return
        }

        val currentRoom = userRooms[userId]
        if (currentRoom != null && currentRoom != roomId) {
            leaveRoom(userId, currentRoom, notify = true)
        }

        val members = roomMembers.computeIfAbsent(roomId) { ConcurrentHashMap.newKeySet() }
        members.add(userId)
        userRooms[userId] = roomId

        val others = members.filter { it != userId }

        sendToUser(
            userId,
            SignalMessage(
                type = "joined",
                roomId = roomId,
                from = "server",
                participants = others
            )
        )

        others.forEach { peer ->
            sendToUser(
                peer,
                SignalMessage(
                    type = "peer-joined",
                    roomId = roomId,
                    from = userId
                )
            )
        }
    }

    private fun forwardPeerMessage(userId: String, incoming: SignalMessage) {
        val targetUserId = incoming.to ?: return
        sendToUser(
            targetUserId,
            incoming.copy(from = userId)
        )
    }

    private fun leaveRoom(userId: String?, roomId: String?, notify: Boolean) {
        if (userId.isNullOrBlank() || roomId.isNullOrBlank()) {
            if (!userId.isNullOrBlank()) {
                userRooms.remove(userId)
            }
            return
        }

        val members = roomMembers[roomId] ?: return
        members.remove(userId)
        userRooms.remove(userId)

        if (notify) {
            members.forEach { peer ->
                sendToUser(
                    peer,
                    SignalMessage(
                        type = "peer-left",
                        roomId = roomId,
                        from = userId
                    )
                )
            }
        }

        if (members.isEmpty()) {
            roomMembers.remove(roomId)
        }
    }

    private fun sendToUser(userId: String, payload: SignalMessage) {
        val sessions = userSessions[userId] ?: return
        sessions.forEach { session ->
            sendToSession(session, payload)
        }
    }

    private fun sendToSession(session: WebSocketSession, payload: SignalMessage) {
        try {
            if (session.isOpen) {
                val lock = sessionLocks.computeIfAbsent(session.id) { Any() }
                synchronized(lock) {
                    if (session.isOpen) {
                        val text = objectMapper.writeValueAsString(payload)
                        session.sendMessage(TextMessage(text))
                    }
                }
            }
        } catch (it: Exception) {
            logger.warn("Failed sending signaling message to session {}", session.id, it)
        }
    }
}
