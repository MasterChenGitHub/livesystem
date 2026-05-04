package com.example.myapi.controller

import com.example.myapi.common.ApiResponse
import com.example.myapi.model.Joke
import com.example.myapi.service.JokeService
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/jokes")
class JokeController(
    private val jokeService: JokeService
) {

    @GetMapping
    fun getRandomJokes(@RequestParam(defaultValue = "3") count: Int): ApiResponse<List<Joke>> {
        return ApiResponse(code = 200, data = jokeService.getRandomJokes(count))
    }
}
