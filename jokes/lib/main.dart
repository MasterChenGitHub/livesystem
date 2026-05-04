import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_server_config.dart';
import 'app.dart';
import 'data/datasources/jokes_database.dart';
import 'data/datasources/jokes_local_data_source.dart';
import 'data/datasources/jokes_remote_data_source.dart';
import 'data/datasources/token_storage.dart';
import 'data/repositories/jokes_repository_impl.dart';
import 'presentation/blocs/auth_bloc.dart';
import 'presentation/blocs/jokes_bloc.dart';
import 'services/friend_directory_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // SQLite for jokes cache.
  final database = await openJokesDatabase();

  // Hive for token persistence.
  await Hive.initFlutter();
  final tokenBox = await Hive.openBox<String>(tokenBoxName);
  final tokenStorage = TokenStorage(tokenBox);
  final friendCacheBox = await Hive.openBox<String>(friendCacheBoxName);
  final hasToken = tokenStorage.hasToken;

  final dio = Dio(
    BaseOptions(
      baseUrl: AppServerConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  // Attach Authorization header automatically when a token is available.
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final skipAuth = options.extra['skipAuth'] == true;
        if (!skipAuth) {
          final token = tokenStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
    ),
  );

  final jokesRepo = JokesRepositoryImpl(
    remote: JokesRemoteDataSource(dio),
    local: JokesLocalDataSource(database),
  );

  final friendDirectoryService = FriendDirectoryService(
    dio: dio,
    tokenStorage: tokenStorage,
    cacheBox: friendCacheBox,
  );
  await friendDirectoryService.loadFriends();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<TokenStorage>.value(value: tokenStorage),
        RepositoryProvider<Dio>.value(value: dio),
        RepositoryProvider<FriendDirectoryService>.value(
          value: friendDirectoryService,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<JokesBloc>(
            create: (_) =>
                JokesBloc(jokesRepo)..add(const JokesFetchRequested()),
          ),
          BlocProvider<AuthBloc>(
            create: (_) => AuthBloc(dio: dio, tokenStorage: tokenStorage),
          ),
        ],
        child: JokesApp(hasToken: hasToken),
      ),
    ),
  );
}
