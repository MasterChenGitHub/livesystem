package com.example.webrtcserver.signaling.model

import com.fasterxml.jackson.annotation.JsonInclude

@JsonInclude(JsonInclude.Include.NON_NULL)
data class SignalMessage(
    val type: String,
    val roomId: String? = null,
    val from: String? = null,
    val to: String? = null,
    val callType: String? = null,
    val sdp: String? = null,
    val candidate: String? = null,
    val sdpMid: String? = null,
    val sdpMLineIndex: Int? = null,
    val participants: List<String>? = null,
    val reason: String? = null
)
