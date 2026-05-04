import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/joke.dart';
import '../blocs/jokes_bloc.dart';

class JokeListPage extends StatelessWidget {
  const JokeListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Joke List')),
      body: BlocBuilder<JokesBloc, JokesState>(
        builder: (context, state) {
          if (state is JokesLoading || state is JokesInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is JokesError) {
            return _ErrorView(
              message: state.message,
              onRetry: () =>
                  context.read<JokesBloc>().add(const JokesRefreshRequested()),
            );
          }
          if (state is JokesLoaded) {
            final jokes = state.jokes;
            if (jokes.isEmpty) {
              return const Center(child: Text('暂无数据'));
            }
            return RefreshIndicator(
              onRefresh: () async =>
                  context.read<JokesBloc>().add(const JokesRefreshRequested()),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: jokes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) => _JokeCard(joke: jokes[index]),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _JokeCard extends StatelessWidget {
  const _JokeCard({required this.joke});

  final Joke joke;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(joke.content,
            style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
