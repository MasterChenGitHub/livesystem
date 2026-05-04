package com.example.myapi.model

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import jakarta.persistence.UniqueConstraint
import java.time.LocalDateTime

@Entity
@Table(
    name = "friendship",
    uniqueConstraints = [UniqueConstraint(columnNames = ["requester_phone", "receiver_phone"])]
)
class Friendship(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long? = null,

    @Column(name = "requester_phone", nullable = false, length = 20)
    var requesterPhone: String,

    @Column(name = "receiver_phone", nullable = false, length = 20)
    var receiverPhone: String,

    @Column(nullable = false)
    var createdAt: LocalDateTime = LocalDateTime.now()
)
