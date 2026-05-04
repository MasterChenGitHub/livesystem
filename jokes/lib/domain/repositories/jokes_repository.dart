import '../../data/models/joke.dart';

abstract class JokesRepository {
  Future<List<Joke>> fetchJokes();
}
