package com.example.myapi.service

import com.example.myapi.model.Joke
import org.springframework.stereotype.Service

@Service
class JokeService {

    private val jokes = listOf(
        Joke(1, "Why do programmers prefer dark mode? Because light attracts bugs!"),
        Joke(2, "Why did the programmer quit his job? Because he didn't get arrays!"),
        Joke(3, "How many programmers does it take to change a light bulb? None, that's a hardware problem."),
        Joke(4, "Why do Java developers wear glasses? Because they don't C#!"),
        Joke(5, "A SQL query walks into a bar, walks up to two tables and asks... Can I join you?"),
        Joke(6, "Why was the JavaScript developer sad? Because he didn't know how to 'null' his feelings."),
        Joke(7, "What do you call a programmer from Finland? Nerdic."),
        Joke(8, "Why did the developer go broke? Because he used up all his cache."),
        Joke(9, "What's a computer's favorite snack? Microchips!"),
        Joke(10, "Why don't programmers like nature? It has too many bugs.")
    )

    fun getRandomJokes(count: Int): List<Joke> {
        val size = count.coerceIn(1, jokes.size)
        return jokes.shuffled().take(size)
    }
}
