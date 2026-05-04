package com.example.myapi.service

import com.aliyun.oss.OSS
import com.aliyun.oss.OSSClientBuilder
import com.aliyun.oss.model.MatchMode
import com.aliyun.oss.model.PolicyConditions
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import java.nio.charset.StandardCharsets
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.text.SimpleDateFormat
import java.util.*

data class UploadToken(
    val uploadUrl: String,
    val token: String,
    val key: String,
    val accessKeyId: String,
    val policy: String
)

@Service
class OssTokenService(
    @Value("\${aliyun.oss.endpoint:}") private val endpoint: String,
    @Value("\${aliyun.oss.access-key-id:}") private val accessKeyId: String,
    @Value("\${aliyun.oss.access-key-secret:}") private val accessKeySecret: String,
    @Value("\${aliyun.oss.bucket:}") private val bucket: String,
    @Value("\${aliyun.oss.public-url-prefix:}") private val publicUrlPrefix: String
) {

    fun generateUploadToken(
        fileType: String = "image", // "image" / "video" / "voice"
        userId: String? = null
    ): UploadToken {
        // Generate key path: chat/2026/04/28/UUID.ext
        val now = System.currentTimeMillis()
        val calendar = Calendar.getInstance()
        calendar.timeInMillis = now
        
        val year = calendar.get(Calendar.YEAR)
        val month = String.format("%02d", calendar.get(Calendar.MONTH) + 1)
        val day = String.format("%02d", calendar.get(Calendar.DAY_OF_MONTH))
        val uuid = UUID.randomUUID().toString()
        
        val ext = when (fileType.lowercase()) {
            "video" -> "mp4"
            "voice" -> "m4a"
            else -> "jpg"
        }
        
        val dir = "chat/$year/$month/$day/"
        val key = "$dir$uuid.$ext"
        
        // Create policy (valid for 30 minutes)
        val expiration = Date(System.currentTimeMillis() + 30 * 60 * 1000)
        val conditions = PolicyConditions()
        conditions.addConditionItem(MatchMode.StartWith, PolicyConditions.COND_KEY, dir)
        conditions.addConditionItem(PolicyConditions.COND_CONTENT_LENGTH_RANGE, 0, 5 * 1024 * 1024 * 1024L) // 5GB
        
        val encodedPolicy = generateEncodedPolicy(bucket, dir, expiration)
        val signature = generateSignature(encodedPolicy, accessKeySecret)
        
        return UploadToken(
            uploadUrl = "https://$bucket.${endpoint.removePrefix("https://").removePrefix("http://")}",
            token = signature,
            key = key,
            accessKeyId = accessKeyId,
            policy = encodedPolicy
        )
    }

    private fun generateEncodedPolicy(
        bucket: String,
        dir: String,
        expiration: Date
    ): String {
        val policyBuilder = StringBuilder()
        policyBuilder.append("{\"expiration\":\"${formatDateISO8601(expiration)}\",")
        policyBuilder.append("\"conditions\":[")
        
        // Add bucket condition
        policyBuilder.append("[\"eq\",\"\$bucket\",\"$bucket\"],")
        
        // Add key condition (startsWith)
        policyBuilder.append("[\"starts-with\",\"\$key\",\"$dir\"],")
        
        // Add content length condition
        policyBuilder.append("[\"content-length-range\",0,5368709120],") // 5GB
        
        // Remove last comma
        policyBuilder.setLength(policyBuilder.length - 1)
        policyBuilder.append("]}")
        
        val policy = policyBuilder.toString()
        return Base64.getEncoder().encodeToString(policy.toByteArray(StandardCharsets.UTF_8))
    }

    private fun generateSignature(encodedPolicy: String, secret: String): String {
        // HMAC-SHA1
        val mac = Mac.getInstance("HmacSHA1")
        val key = SecretKeySpec(secret.toByteArray(StandardCharsets.UTF_8), 0, secret.length, "HmacSHA1")
        mac.init(key)
        val signature = mac.doFinal(encodedPolicy.toByteArray(StandardCharsets.UTF_8))
        
        return String(Base64.getEncoder().encode(signature), StandardCharsets.UTF_8)
    }

    private fun formatDateISO8601(date: Date): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'")
        sdf.timeZone = TimeZone.getTimeZone("UTC")
        return sdf.format(date)
    }
}
