import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jokes/app.dart';
import 'package:jokes/data/datasources/jokes_database.dart';
import 'package:jokes/data/datasources/jokes_local_data_source.dart';
import 'package:jokes/data/datasources/jokes_remote_data_source.dart';
import 'package:jokes/data/datasources/token_storage.dart';
import 'package:jokes/data/repositories/jokes_repository_impl.dart';
import 'package:jokes/presentation/blocs/auth_bloc.dart';
import 'package:jokes/presentation/blocs/jokes_bloc.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('Joke list page renders app bar', (WidgetTester tester) async {
    await Hive.initFlutter();
    final tokenBox = await Hive.openBox<String>(tokenBoxName);
    final tokenStorage = TokenStorage(tokenBox);

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async => createJokesSchema(db),
    );
    addTearDown(() async => db.close());

    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080/api'));
    final jokesRepo = JokesRepositoryImpl(
      remote: JokesRemoteDataSource(dio),
      local: JokesLocalDataSource(db),
    );

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<TokenStorage>.value(value: tokenStorage),
          RepositoryProvider<Dio>.value(value: dio),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<JokesBloc>(
              create: (_) => JokesBloc(jokesRepo),
            ),
            BlocProvider<AuthBloc>(
              create: (_) =>
                  AuthBloc(dio: dio, tokenStorage: tokenStorage),
            ),
          ],
          child: const JokesApp(hasToken: false),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Joke List'), findsOneWidget);
  });
}
