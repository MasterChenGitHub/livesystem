import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';

import '../../data/datasources/token_storage.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

const Object _authSentinel = Object();

class AuthFormState {
  const AuthFormState({
    this.phone = '',
    this.code = '',
    this.countdown = 0,
    this.isSendingCode = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.isSuccess = false,
  });

  final String phone;
  final String code;
  final int countdown;
  final bool isSendingCode;
  final bool isSubmitting;
  final String? errorMessage;
  final bool isSuccess;

  static final _phoneRegex = RegExp(r'^1[3-9]\d{9}$');

  bool get isPhoneValid => _phoneRegex.hasMatch(phone);
  bool get canSendCode =>
      isPhoneValid && countdown == 0 && !isSendingCode && !isSubmitting;
  bool get canSubmit =>
      isPhoneValid && code.length == 6 && !isSubmitting && !isSendingCode;

  AuthFormState copyWith({
    String? phone,
    String? code,
    int? countdown,
    bool? isSendingCode,
    bool? isSubmitting,
    Object? errorMessage = _authSentinel,
    bool? isSuccess,
  }) {
    return AuthFormState(
      phone: phone ?? this.phone,
      code: code ?? this.code,
      countdown: countdown ?? this.countdown,
      isSendingCode: isSendingCode ?? this.isSendingCode,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage == _authSentinel
          ? this.errorMessage
          : errorMessage as String?,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class AuthEvent {
  const AuthEvent();
}

class AuthPhoneChanged extends AuthEvent {
  const AuthPhoneChanged(this.phone);
  final String phone;
}

class AuthCodeChanged extends AuthEvent {
  const AuthCodeChanged(this.code);
  final String code;
}

class AuthSendCodeRequested extends AuthEvent {
  const AuthSendCodeRequested();
}

class AuthSubmitRequested extends AuthEvent {
  const AuthSubmitRequested();
}

class _AuthCountdownTicked extends AuthEvent {
  const _AuthCountdownTicked(this.remaining);
  final int remaining;
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

class AuthBloc extends Bloc<AuthEvent, AuthFormState> {
  AuthBloc({required Dio dio, required TokenStorage tokenStorage})
      : _dio = dio,
        _tokenStorage = tokenStorage,
        super(const AuthFormState()) {
    on<AuthPhoneChanged>(_onPhoneChanged);
    on<AuthCodeChanged>(_onCodeChanged);
    on<AuthSendCodeRequested>(_onSendCode);
    on<AuthSubmitRequested>(_onSubmit);
    on<_AuthCountdownTicked>(_onCountdownTicked);
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;
  Timer? _countdownTimer;

  void _onPhoneChanged(AuthPhoneChanged e, Emitter<AuthFormState> emit) =>
      emit(state.copyWith(phone: e.phone.trim(), errorMessage: null));

  void _onCodeChanged(AuthCodeChanged e, Emitter<AuthFormState> emit) =>
      emit(state.copyWith(code: e.code.trim(), errorMessage: null));

  Future<void> _onSendCode(
    AuthSendCodeRequested event,
    Emitter<AuthFormState> emit,
  ) async {
    if (!state.canSendCode) return;
    emit(state.copyWith(isSendingCode: true, errorMessage: null));
    try {
      await _dio.post<dynamic>('/auth/getCode', data: {'phone': state.phone});
      emit(state.copyWith(isSendingCode: false, countdown: 60));
      _startCountdown();
    } on DioException catch (e) {
      final msg = _extractError(e) ?? '发送失败，请稍后重试';
      emit(state.copyWith(isSendingCode: false, errorMessage: msg));
    } catch (_) {
      emit(state.copyWith(isSendingCode: false, errorMessage: '发送失败，请稍后重试'));
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.countdown - 1;
      if (remaining <= 0) {
        _countdownTimer?.cancel();
        add(const _AuthCountdownTicked(0));
      } else {
        add(_AuthCountdownTicked(remaining));
      }
    });
  }

  void _onCountdownTicked(
    _AuthCountdownTicked e,
    Emitter<AuthFormState> emit,
  ) =>
      emit(state.copyWith(countdown: e.remaining));

  Future<void> _onSubmit(
    AuthSubmitRequested event,
    Emitter<AuthFormState> emit,
  ) async {
    if (!state.canSubmit) return;
    emit(state.copyWith(isSubmitting: true, errorMessage: null));
    try {
      final response = await _dio.post<dynamic>(
        '/auth/login',
        data: {'phone': state.phone, 'verificationCode': state.code},
      );

      final body = response.data;
      String token = '';
      String phone = state.phone;
      String nickname = '';
      String avatar = '';

      if (body is Map<String, dynamic>) {
        token = body['token']?.toString() ?? '';
        phone = body['phone']?.toString() ?? phone;
        nickname = body['nickname']?.toString() ?? '';
        avatar = body['avatar']?.toString() ?? '';

        if (token.isEmpty) {
          final data = body['data'];
          if (data is Map<String, dynamic>) {
            token = data['token']?.toString() ?? '';
            phone = data['phone']?.toString() ?? phone;
            nickname = data['nickname']?.toString() ?? '';
            avatar = data['avatar']?.toString() ?? '';
          }
        }
      }

      if (token.isNotEmpty) {
        final safeNickname = nickname.isNotEmpty
            ? nickname
            : (phone.length >= 4
                ? '用户${phone.substring(phone.length - 4)}'
                : '用户');
        await _tokenStorage.saveToken(token);
        await _tokenStorage.savePhone(phone);
        await _tokenStorage.saveNickname(safeNickname);
        await _tokenStorage.saveAvatar(avatar);
      }

      emit(state.copyWith(isSubmitting: false, isSuccess: true));
    } on DioException catch (e) {
      final msg = _extractError(e) ?? '登录失败，请检查验证码';
      emit(state.copyWith(isSubmitting: false, errorMessage: msg));
    } catch (_) {
      emit(state.copyWith(isSubmitting: false, errorMessage: '登录失败'));
    }
  }

  String? _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final msg = data['message'] ?? data['error'];
      if (msg != null) return msg.toString();
    }
    return null;
  }

  @override
  Future<void> close() {
    _countdownTimer?.cancel();
    return super.close();
  }
}
