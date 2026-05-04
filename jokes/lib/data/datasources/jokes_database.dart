import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

const String jokesCacheTable = 'jokes_cache';

Future<void> createJokesSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS $jokesCacheTable (
      id TEXT PRIMARY KEY,
      content TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
}

Future<Database> openJokesDatabase({String? databasePath}) async {
  final path =
      databasePath ?? join(await getDatabasesPath(), 'jokes_local_cache.db');

  return openDatabase(
    path,
    version: 1,
    onCreate: (db, version) async {
      await createJokesSchema(db);
    },
  );
}
