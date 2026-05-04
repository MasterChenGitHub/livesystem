package com.example.myapi.config

import org.redisson.Redisson
import org.redisson.api.RedissonClient
import org.redisson.config.Config
import org.springframework.beans.factory.annotation.Value
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration

@Configuration
class RedissonConfig {

    @Bean(destroyMethod = "shutdown")
    @ConditionalOnProperty(prefix = "cache.redisson", name = ["enabled"], havingValue = "true")
    fun redissonClient(
        @Value("\${cache.redisson.host:localhost}") host: String,
        @Value("\${cache.redisson.port:6379}") port: Int,
        @Value("\${cache.redisson.password:}") password: String,
        @Value("\${cache.redisson.database:0}") database: Int
    ): RedissonClient {
        val config = Config()
        config.useSingleServer().apply {
            address = "redis://$host:$port"
            this.database = database
            if (password.isNotBlank()) {
                this.password = password
            }
        }
        return Redisson.create(config)
    }
}
