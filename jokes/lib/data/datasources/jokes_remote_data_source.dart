import 'package:dio/dio.dart';

import '../models/joke.dart';

class JokesRemoteDataSource {
  JokesRemoteDataSource(this._dio);

  final Dio _dio;

  static const String jokesApi = '/jokes';

  Future<List<Joke>> fetchJokes() async {
    final response = await _dio.get<dynamic>(jokesApi);
    final data = response.data;

    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(Joke.fromJson)
          .toList(growable: false);
    }

    if (data is Map<String, dynamic>) {
      final possibleList = data['data'] ?? data['jokes'] ?? data['results'];
      if (possibleList is List) {
        return possibleList
            .whereType<Map<String, dynamic>>()
            .map(Joke.fromJson)
            .toList(growable: false);
      }

      return [Joke.fromJson(data)];
    }

    return const [];
  }
}
