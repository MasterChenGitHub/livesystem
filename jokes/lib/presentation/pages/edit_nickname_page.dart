import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/token_storage.dart';

class EditNicknamePage extends StatefulWidget {
  const EditNicknamePage({super.key, required this.initialNickname});

  final String initialNickname;

  @override
  State<EditNicknamePage> createState() => _EditNicknamePageState();
}

class _EditNicknamePageState extends State<EditNicknamePage> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNickname);
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave {
    final value = _controller.text.trim();
    return !_saving && value.isNotEmpty && value != widget.initialNickname;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final nickname = _controller.text.trim();

    setState(() => _saving = true);
    try {
      final dio = context.read<Dio>();
      final storage = context.read<TokenStorage>();
      final res = await dio.post<Map<String, dynamic>>(
        '/auth/profile/nickname',
        data: {'nickname': nickname},
      );
      if (res.statusCode != 200) {
        throw Exception('修改失败');
      }

      await storage.saveNickname(nickname);
      if (!mounted) return;
      Navigator.of(context).pop(nickname);
    } on DioException catch (e) {
      final msg = e.response?.data is Map<String, dynamic>
          ? (e.response?.data['message'] ?? e.response?.data['error'])?.toString()
          : null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? '修改失败，请稍后再试')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('修改失败，请稍后再试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('更改名字'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _canSave ? const Color(0xFF07C160) : Colors.white12,
                foregroundColor: _canSave ? Colors.white : Colors.white54,
              ),
              onPressed: _canSave ? _save : null,
              child: Text(_saving ? '保存中' : '保存'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              maxLength: 20,
              style: const TextStyle(color: Colors.white, fontSize: 20),
              decoration: const InputDecoration(
                counterText: '',
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF07C160)),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF07C160), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '好名字可以让你的朋友更容易记住你。',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
