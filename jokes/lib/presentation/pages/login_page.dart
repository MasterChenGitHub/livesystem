import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/auth_bloc.dart';
import 'main_tab_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();

  @override
  void dispose() {
    _phoneFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthFormState>(
      listener: (context, state) {
        if (state.isSuccess) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const MainTabPage()),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('手机号登录')),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: BlocBuilder<AuthBloc, AuthFormState>(
                builder: (context, formState) {
                  final bloc = context.read<AuthBloc>();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PhoneField(
                        focusNode: _phoneFocus,
                        onChanged: (v) =>
                            bloc.add(AuthPhoneChanged(v)),
                        nextFocus: _codeFocus,
                        isValid: formState.isPhoneValid ||
                            formState.phone.isEmpty,
                      ),
                      const SizedBox(height: 16),
                      _CodeField(
                        focusNode: _codeFocus,
                        onChanged: (v) =>
                            bloc.add(AuthCodeChanged(v)),
                        canSend: formState.canSendCode,
                        countdown: formState.countdown,
                        isSending: formState.isSendingCode,
                        onSendCode: () =>
                            bloc.add(const AuthSendCodeRequested()),
                      ),
                      if (formState.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          formState.errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: formState.canSubmit
                            ? () =>
                                bloc.add(const AuthSubmitRequested())
                            : null,
                        child: formState.isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('登录'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.focusNode,
    required this.onChanged,
    required this.nextFocus,
    required this.isValid,
  });

  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final FocusNode nextFocus;
  final bool isValid;

  @override
  Widget build(BuildContext context) {
    return TextField(
      focusNode: focusNode,
      keyboardType: TextInputType.phone,
      maxLength: 11,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: '手机号',
        prefixIcon: const Icon(Icons.phone_android_outlined),
        border: const OutlineInputBorder(),
        counterText: '',
        errorText: isValid ? null : '请输入正确的手机号',
      ),
      onChanged: onChanged,
      onSubmitted: (_) => nextFocus.requestFocus(),
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.focusNode,
    required this.onChanged,
    required this.canSend,
    required this.countdown,
    required this.isSending,
    required this.onSendCode,
  });

  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool canSend;
  final int countdown;
  final bool isSending;
  final VoidCallback onSendCode;

  @override
  Widget build(BuildContext context) {
    final sendLabel = countdown > 0
        ? '重发(${countdown}s)'
        : isSending
            ? '发送中...'
            : '获取验证码';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            focusNode: focusNode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '验证码',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 56,
          child: OutlinedButton(
            onPressed: canSend ? onSendCode : null,
            child: Text(sendLabel),
          ),
        ),
      ],
    );
  }
}
