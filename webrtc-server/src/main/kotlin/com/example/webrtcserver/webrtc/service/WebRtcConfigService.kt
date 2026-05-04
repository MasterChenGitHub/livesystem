package com.example.webrtcserver.webrtc.service

import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service

@Service
class WebRtcConfigService {

    @Value("\${webrtc.mode:p2p}")
    private lateinit var mode: String

    @Value("\${webrtc.stun.url:}")
    private lateinit var stunUrl: String

    @Value("\${webrtc.turn.url:}")
    private lateinit var turnUrl: String

    @Value("\${webrtc.turn.username:}")
    private lateinit var turnUsername: String

    @Value("\${webrtc.turn.credential:}")
    private lateinit var turnCredential: String

    data class IceServer(
        val urls: List<String>,
        val username: String? = null,
        val credential: String? = null
    )

    private fun parseUrls(raw: String): List<String> {
        return raw.split(",")
            .map { it.trim() }
            .filter { it.isNotBlank() }
    }

    fun getIceServers(): List<IceServer> {
        val servers = mutableListOf<IceServer>()
        val stunUrls = parseUrls(stunUrl)
        val turnUrls = parseUrls(turnUrl)

        if (stunUrls.isNotEmpty()) {
            servers.add(IceServer(urls = stunUrls))
        }

        if (turnUrls.isNotEmpty() && turnUsername.isNotBlank() && turnCredential.isNotBlank()) {
            servers.add(
                IceServer(
                    urls = turnUrls,
                    username = turnUsername,
                    credential = turnCredential
                )
            )
        }

        return if (servers.isEmpty()) {
            listOf(IceServer(urls = listOf("stun:stun.qq.com:3478", "stun:stun.miwifi.com:3478")))
        } else {
            servers
        }
    }
}
