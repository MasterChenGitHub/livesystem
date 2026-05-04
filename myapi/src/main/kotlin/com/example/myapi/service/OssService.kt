package com.example.myapi.service

import com.aliyun.oss.OSS
import com.aliyun.oss.OSSClientBuilder
import com.aliyun.oss.model.ObjectMetadata
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import java.io.ByteArrayInputStream
import java.time.LocalDate
import java.util.UUID

@Service
class OssService(
    @Value("\${aliyun.oss.endpoint:}") private val endpoint: String,
    @Value("\${aliyun.oss.access-key-id:}") private val accessKeyId: String,
    @Value("\${aliyun.oss.access-key-secret:}") private val accessKeySecret: String,
    @Value("\${aliyun.oss.bucket:}") private val bucket: String,
    @Value("\${aliyun.oss.public-url-prefix:}") private val publicUrlPrefix: String,
) {

    data class UploadResult(val key: String, val url: String)

    fun uploadImage(bytes: ByteArray, suffix: String, contentType: String, isThumb: Boolean = false): UploadResult {
        require(endpoint.isNotBlank()) { "OSS endpoint is not configured" }
        require(accessKeyId.isNotBlank()) { "OSS accessKeyId is not configured" }
        require(accessKeySecret.isNotBlank()) { "OSS accessKeySecret is not configured" }
        require(bucket.isNotBlank()) { "OSS bucket is not configured" }

        val date = LocalDate.now()
        val folder = if (isThumb) {
            "chat-images/${date.year}/${date.monthValue}/${date.dayOfMonth}/thumb"
        } else {
            "chat-images/${date.year}/${date.monthValue}/${date.dayOfMonth}"
        }
        val key = "$folder/${UUID.randomUUID()}.$suffix"

        val ossClient: OSS = OSSClientBuilder().build(endpoint, accessKeyId, accessKeySecret)
        try {
            val metadata = ObjectMetadata().apply {
                this.contentType = contentType
                this.contentLength = bytes.size.toLong()
            }
            ByteArrayInputStream(bytes).use { input ->
                ossClient.putObject(bucket, key, input, metadata)
            }
        } finally {
            ossClient.shutdown()
        }

        return UploadResult(key = key, url = toPublicUrl(key))
    }

    private fun toPublicUrl(key: String): String {
        if (publicUrlPrefix.isNotBlank()) {
            return "${publicUrlPrefix.trimEnd('/')}/$key"
        }
        return "https://$bucket.${endpoint.removePrefix("https://").removePrefix("http://")}/$key"
    }
}
