import '../../domain/repositories/jokes_repository.dart';
import '../datasources/jokes_local_data_source.dart';
import '../datasources/jokes_remote_data_source.dart';
import '../models/joke.dart';

class JokesRepositoryImpl implements JokesRepository {
  JokesRepositoryImpl({
    required JokesRemoteDataSource remote,
    required JokesLocalDataSource local,
  })  : _remote = remote,
        _local = local;

  final JokesRemoteDataSource _remote;
  final JokesLocalDataSource _local;

  @override
  Future<List<Joke>> fetchJokes() async {
    try {
      final jokes = await _remote.fetchJokes();
      if (jokes.isNotEmpty) {
        await _local.saveJokes(jokes);
      }
      return jokes;
    } catch (_) {
      final cached = await _local.getCachedJokes();
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }
}
