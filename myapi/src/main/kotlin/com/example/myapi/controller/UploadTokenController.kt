package com.example.myapi.controller

import com.example.myapi.service.AuthService
import com.example.myapi.service.OssTokenService
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/api/upload")
class UploadTokenController(
    private val ossTokenService: OssTokenService,
    private val authService: AuthService
) {

    @PostMapping("/token")
    fun getUploadToken(
        @RequestHeader("Authorization") authHeader: String,
        @RequestParam(defaultValue = "image") fileType: String
    ): ResponseEntity<Map<String, Any>> {
        // Validate token
        val token = authHeader.removePrefix("Bearer ").trim()
        val phone = authService.resolvePhoneByToken(token)
            ?: return ResponseEntity.status(401).body(mapOf("error" to "Unauthorized"))
        
        // Generate OSS token
        val uploadToken = ossTokenService.generateUploadToken(fileType, phone)
        
        return ResponseEntity.ok(mapOf(
            "uploadUrl" to uploadToken.uploadUrl,
            "token" to uploadToken.token,
            "key" to uploadToken.key,
            "accessKeyId" to uploadToken.accessKeyId,
            "policy" to uploadToken.policy
        ))
    }
}
