package com.example.webrtcserver.config

import org.springframework.context.annotation.Configuration
import org.springframework.web.socket.config.annotation.EnableWebSocket
import org.springframework.web.socket.config.annotation.WebSocketConfigurer
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry
import com.example.webrtcserver.signaling.ws.SignalingWebSocketHandler

@Configuration
@EnableWebSocket
class WebSocketConfig(
    private val signalingWebSocketHandler: SignalingWebSocketHandler
) : WebSocketConfigurer {

    override fun registerWebSocketHandlers(registry: WebSocketHandlerRegistry) {
        registry
            .addHandler(signalingWebSocketHandler, "/ws/signaling")
            .setAllowedOrigins("*")
    }
}
