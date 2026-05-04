package com.example.webrtcserver.webrtc.controller

import com.example.webrtcserver.common.ApiResponse
import com.example.webrtcserver.webrtc.service.WebRtcConfigService
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/webrtc")
class WebRtcController(
    private val webRtcConfigService: WebRtcConfigService
) {

    @GetMapping("/config")
    fun getConfig(): ResponseEntity<ApiResponse<Map<String, Any>>> {
        val iceServers = webRtcConfigService.getIceServers()
        return ResponseEntity.ok(
            ApiResponse(
                code = 200,
                data = mapOf(
                    "iceServers" to iceServers
                )
            )
        )
    }
}
