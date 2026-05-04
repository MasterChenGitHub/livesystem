package com.example.myapi.controller

import com.example.myapi.service.AuthService
import com.example.myapi.service.MessageService
import com.example.myapi.ws.ChatWebSocketGateway
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/api/messages")
class MessageController(
    private val messageService: MessageService,
    private val authService: AuthService,
    private val chatWebSocketGateway: ChatWebSocketGateway
) {
    
    sealed class AuthResult {
        data class Success(val phone: String) : AuthResult()
        object Invalid : AuthResult()
    }
    
    private fun validateToken(authHeader: String?): AuthResult {
        return try {
            val token = authHeader?.removePrefix("Bearer ")?.trim()
                ?: return AuthResult.Invalid
            val phone = authService.resolvePhoneByToken(token)
                ?: return AuthResult.Invalid
            AuthResult.Success(phone)
        } catch (e: Exception) {
            AuthResult.Invalid
        }
    }
    
    /**
     * Send a message to a friend
     * POST /api/messages/send
     * Body: { "receiverPhone": "xxx", "content": "xxx", "type": "text", "imageUrl": null }
     */
    @PostMapping("/send")
    fun sendMessage(
        @RequestHeader("Authorization") authHeader: String?,
        @RequestBody request: SendMessageRequest
    ): ResponseEntity<Any> {
        val authResult = validateToken(authHeader)
        if (authResult !is AuthResult.Success) {
            return ResponseEntity(
                mapOf("error" to "Invalid or missing token"),
                HttpStatus.UNAUTHORIZED
            )
        }
        
        val message = messageService.sendMessage(
            senderPhone = authResult.phone,
            receiverPhone = request.receiverPhone,
            content = request.content,
            type = request.type ?: "text",
            imageUrl = request.imageUrl,
            thumbUrl = request.thumbUrl,
            imageWidth = request.imageWidth,
            imageHeight = request.imageHeight,
            imageSize = request.imageSize,
            videoUrl = request.videoUrl,
            videoThumbUrl = request.videoThumbUrl,
            videoDuration = request.videoDuration,
            videoWidth = request.videoWidth,
            videoHeight = request.videoHeight,
            voiceUrl = request.voiceUrl,
            voiceDuration = request.voiceDuration,
        )

        chatWebSocketGateway.pushChatMessage(request.receiverPhone, message)
        
        return ResponseEntity.ok(message)
    }
    
    /**
     * Get conversation messages with a friend
     * GET /api/messages/list?friendPhone=xxx&limit=100
     */
    @GetMapping("/list")
    fun getConversation(
        @RequestHeader("Authorization") authHeader: String?,
        @RequestParam friendPhone: String,
        @RequestParam(defaultValue = "100") limit: Int
    ): ResponseEntity<Any> {
        val authResult = validateToken(authHeader)
        if (authResult !is AuthResult.Success) {
            return ResponseEntity(
                mapOf("error" to "Invalid or missing token"),
                HttpStatus.UNAUTHORIZED
            )
        }
        
        val messages = if (limit > 0) {
            messageService.getConversationLimited(authResult.phone, friendPhone, limit)
        } else {
            messageService.getConversation(authResult.phone, friendPhone)
        }
        
        return ResponseEntity.ok(messages)
    }

    /**
     * Mark messages from a friend as read
     * POST /api/messages/read
     * Body: { "friendPhone": "xxx" }
     */
    @PostMapping("/read")
    fun markRead(
        @RequestHeader("Authorization") authHeader: String?,
        @RequestBody request: MarkReadRequest
    ): ResponseEntity<Any> {
        val authResult = validateToken(authHeader)
        if (authResult !is AuthResult.Success) {
            return ResponseEntity(
                mapOf("error" to "Invalid or missing token"),
                HttpStatus.UNAUTHORIZED
            )
        }

        val updated = messageService.markConversationRead(
            myPhone = authResult.phone,
            friendPhone = request.friendPhone
        )

        if (updated > 0) {
            chatWebSocketGateway.pushReadReceipt(
                toPhone = request.friendPhone,
                readerId = authResult.phone
            )
        }

        return ResponseEntity.ok(mapOf("updated" to updated))
    }

    /**
     * Delete selected messages in one conversation
     * POST /api/messages/delete
     * Body: { "friendPhone": "xxx", "messageIds": [1,2,3] }
     */
    @PostMapping("/delete")
    fun deleteMessages(
        @RequestHeader("Authorization") authHeader: String?,
        @RequestBody request: DeleteMessagesRequest,
    ): ResponseEntity<Any> {
        val authResult = validateToken(authHeader)
        if (authResult !is AuthResult.Success) {
            return ResponseEntity(
                mapOf("error" to "Invalid or missing token"),
                HttpStatus.UNAUTHORIZED
            )
        }

        val deleted = messageService.deleteConversationMessagesByIds(
            myPhone = authResult.phone,
            friendPhone = request.friendPhone,
            messageIds = request.messageIds,
        )

        return ResponseEntity.ok(mapOf("deleted" to deleted))
    }
}

data class SendMessageRequest(
    val receiverPhone: String,
    val content: String,
    val type: String? = "text",
    val imageUrl: String? = null,
    val thumbUrl: String? = null,
    val imageWidth: Int? = null,
    val imageHeight: Int? = null,
    val imageSize: Long? = null,
    val videoUrl: String? = null,
    val videoThumbUrl: String? = null,
    val videoDuration: Int? = null,
    val videoWidth: Int? = null,
    val videoHeight: Int? = null,
    val voiceUrl: String? = null,
    val voiceDuration: Int? = null,
)

data class MarkReadRequest(
    val friendPhone: String
)

data class DeleteMessagesRequest(
    val friendPhone: String,
    val messageIds: List<Long>,
)
