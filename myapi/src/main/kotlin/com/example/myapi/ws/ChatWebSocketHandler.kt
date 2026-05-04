package com.example.myapi.ws

import com.example.myapi.service.AuthService
import com.example.myapi.service.FriendService
import org.springframework.stereotype.Component
import org.springframework.web.socket.CloseStatus
import org.springframework.web.socket.TextMessage
import org.springframework.web.socket.WebSocketSession
import org.springframework.web.socket.handler.TextWebSocketHandler
import tools.jackson.module.kotlin.jacksonObjectMapper
import java.util.concurrent.ConcurrentHashMap

@Component
class ChatWebSocketHandler(
    private val authService: AuthService,
    private val friendService: FriendService,
    private val chatWebSocketGateway: ChatWebSocketGateway
) : TextWebSocketHandler() {

    private val objectMapper = jacksonObjectMapper()
    private val sessionPhoneMap = ConcurrentHashMap<String, String>()

    override fun afterConnectionEstablished(session: WebSocketSession) {
        val token = session.uri?.query
            ?.split("&")
            ?.mapNotNull {
                val pair = it.split("=", limit = 2)
                if (pair.size == 2) pair[0] to pair[1] else null
            }
            ?.firstOrNull { it.first == "token" }
            ?.second
            ?.trim()

        val phone = token?.let { authService.resolvePhoneByToken(it) }
        if (phone.isNullOrBlank()) {
            session.close(CloseStatus.POLICY_VIOLATION)
            return
        }

        sessionPhoneMap[session.id] = phone
        chatWebSocketGateway.register(phone, session)
        notifyFriendsPresence(phone, true)
    }

    override fun handleTextMessage(session: WebSocketSession, message: TextMessage) {
        val me = sessionPhoneMap[session.id] ?: return
        val payload = try {
            objectMapper.readValue(message.payload, Map::class.java)
        } catch (_: Exception) {
            return
        }

        val type = payload["type"]?.toString() ?: return
        if (type == "typing") {
            val to = payload["to"]?.toString()?.trim().orEmpty()
            if (to.isBlank()) return
            val isTyping = payload["isTyping"]?.toString()?.toBoolean() ?: false
            chatWebSocketGateway.pushTyping(toPhone = to, fromUserId = me, isTyping = isTyping)
        }
    }

    override fun handleTransportError(session: WebSocketSession, exception: Throwable) {
        removeSession(session)
        if (session.isOpen) {
            session.close(CloseStatus.SERVER_ERROR)
        }
    }

    override fun afterConnectionClosed(session: WebSocketSession, status: CloseStatus) {
        removeSession(session)
    }

    private fun removeSession(session: WebSocketSession) {
        val phone = sessionPhoneMap.remove(session.id) ?: return
        chatWebSocketGateway.unregister(phone, session)
        if (!chatWebSocketGateway.isOnline(phone)) {
            notifyFriendsPresence(phone, false)
        }
    }

    private fun notifyFriendsPresence(phone: String, online: Boolean) {
        val friends = friendService.listFriendPhonesByPhone(phone)
        friends.forEach { friendPhone ->
            chatWebSocketGateway.pushPresence(
                toPhone = friendPhone,
                userId = phone,
                online = online
            )
        }
    }
}
