import 'package:flutter/material.dart';

import 'presentation/pages/login_page.dart';
import 'presentation/pages/main_tab_page.dart';

class JokesApp extends StatelessWidget {
  const JokesApp({super.key, required this.hasToken});

  final bool hasToken;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jokes',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: hasToken ? const MainTabPage() : const LoginPage(),
    );
  }
}
