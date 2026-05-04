package com.example.myapi.repository

import com.example.myapi.model.User
import org.springframework.data.jpa.repository.JpaRepository

interface UserRepository : JpaRepository<User, Long> {
    fun existsByPhone(phone: String): Boolean
    fun findByPhone(phone: String): User?
    fun findAllByPhoneNot(phone: String): List<User>
}
