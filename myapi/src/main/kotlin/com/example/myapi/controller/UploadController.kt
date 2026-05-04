package com.example.myapi.controller

import com.example.myapi.service.AuthService
import com.example.myapi.service.OssService
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile

@RestController
@RequestMapping("/api/upload")
class UploadController(
    private val authService: AuthService,
    private val ossService: OssService,
) {

    @PostMapping("/image")
    fun uploadImage(
        @RequestHeader("Authorization", required = false) authHeader: String?,
        @RequestParam("file") file: MultipartFile,
        @RequestParam("thumb", required = false) thumb: MultipartFile?,
        @RequestParam("width", required = false) width: Int?,
        @RequestParam("height", required = false) height: Int?,
        @RequestParam("size", required = false) size: Long?,
    ): ResponseEntity<Any> {
        val token = authHeader?.removePrefix("Bearer ")?.trim().orEmpty()
        val phone = authService.resolvePhoneByToken(token)
        if (phone.isNullOrBlank()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(mapOf("error" to "Invalid or missing token"))
        }

        if (file.isEmpty) {
            return ResponseEntity.badRequest().body(mapOf("error" to "file is required"))
        }

        val fileSuffix = file.originalFilename
            ?.substringAfterLast('.', "jpg")
            ?.lowercase()
            ?: "jpg"

        val imageResult = ossService.uploadImage(
            bytes = file.bytes,
            suffix = fileSuffix,
            contentType = file.contentType ?: "image/jpeg",
            isThumb = false,
        )

        val thumbResult = if (thumb != null && !thumb.isEmpty) {
            val thumbSuffix = thumb.originalFilename
                ?.substringAfterLast('.', "jpg")
                ?.lowercase()
                ?: "jpg"
            ossService.uploadImage(
                bytes = thumb.bytes,
                suffix = thumbSuffix,
                contentType = thumb.contentType ?: "image/jpeg",
                isThumb = true,
            )
        } else null

        return ResponseEntity.ok(
            mapOf(
                "url" to imageResult.url,
                "thumbUrl" to (thumbResult?.url ?: imageResult.url),
                "width" to width,
                "height" to height,
                "size" to (size ?: file.size),
            )
        )
    }
}
