import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/joke.dart';
import '../../domain/repositories/jokes_repository.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class JokesEvent {
  const JokesEvent();
}

class JokesFetchRequested extends JokesEvent {
  const JokesFetchRequested();
}

class JokesRefreshRequested extends JokesEvent {
  const JokesRefreshRequested();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class JokesState {
  const JokesState();
}

class JokesInitial extends JokesState {
  const JokesInitial();
}

class JokesLoading extends JokesState {
  const JokesLoading();
}

class JokesLoaded extends JokesState {
  const JokesLoaded(this.jokes);
  final List<Joke> jokes;
}

class JokesError extends JokesState {
  const JokesError(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

class JokesBloc extends Bloc<JokesEvent, JokesState> {
  JokesBloc(this._repository) : super(const JokesInitial()) {
    on<JokesFetchRequested>(_onFetch);
    on<JokesRefreshRequested>(_onRefresh);
  }

  final JokesRepository _repository;

  Future<void> _onFetch(
    JokesFetchRequested event,
    Emitter<JokesState> emit,
  ) async {
    emit(const JokesLoading());
    try {
      final jokes = await _repository.fetchJokes();
      emit(JokesLoaded(jokes));
    } catch (e) {
      emit(JokesError(e.toString()));
    }
  }

  Future<void> _onRefresh(
    JokesRefreshRequested event,
    Emitter<JokesState> emit,
  ) async {
    emit(const JokesLoading());
    try {
      final jokes = await _repository.fetchJokes();
      emit(JokesLoaded(jokes));
    } catch (e) {
      emit(JokesError(e.toString()));
    }
  }
}
