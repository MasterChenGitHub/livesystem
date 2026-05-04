import 'package:sqflite/sqflite.dart';

import '../models/joke.dart';
import 'jokes_database.dart';

class JokesLocalDataSource {
  JokesLocalDataSource(this._database);

  final Database _database;

  Future<void> saveJokes(List<Joke> jokes) async {
    final batch = _database.batch();
    batch.delete(jokesCacheTable);

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final joke in jokes) {
      batch.insert(
        jokesCacheTable,
        {
          'id': joke.id,
          'content': joke.content,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Joke>> getCachedJokes() async {
    final rows = await _database.query(
      jokesCacheTable,
      columns: ['id', 'content'],
      orderBy: 'updated_at DESC',
    );

    return rows
        .map(
          (row) => Joke(
            id: row['id']?.toString() ?? '',
            content: row['content']?.toString() ?? '',
          ),
        )
        .where((joke) => joke.content.isNotEmpty)
        .toList(growable: false);
  }
}
