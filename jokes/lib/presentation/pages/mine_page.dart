import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/token_storage.dart';
import 'avatar_page.dart';
import 'edit_nickname_page.dart';
import 'login_page.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  String _phone = '';
  String _nickname = '';
  String _avatar = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadProfile();
  }

  void _reloadProfile() {
    final storage = context.read<TokenStorage>();
    final phone = storage.getPhone() ?? '';
    final nickname =
        storage.getNickname() ??
        (phone.length >= 4 ? '用户${phone.substring(phone.length - 4)}' : '未设置昵称');
    final avatar = storage.getAvatar() ?? '';
    _phone = phone;
    _nickname = nickname;
    _avatar = avatar;
  }

  Future<void> _openAvatarPage() async {
    final updated = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => AvatarPage(currentAvatar: _avatar),
      ),
    );
    if (!mounted) return;
    if (updated != null && updated.isNotEmpty) {
      setState(() {
        _avatar = updated;
      });
    } else {
      setState(_reloadProfile);
    }
  }

  Future<void> _openEditNicknamePage() async {
    final updated = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => EditNicknamePage(initialNickname: _nickname),
      ),
    );
    if (!mounted) return;
    if (updated != null && updated.isNotEmpty) {
      setState(() {
        _nickname = updated;
      });
    } else {
      setState(_reloadProfile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.read<TokenStorage>();

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _openAvatarPage,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundImage:
                                _avatar.isNotEmpty ? NetworkImage(_avatar) : null,
                            child: _avatar.isEmpty
                                ? const Icon(Icons.person, size: 30)
                                : null,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.edit,
                                size: 14,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: _openEditNicknamePage,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _nickname,
                                    style: Theme.of(context).textTheme.titleMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: Colors.black45,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _phone.isEmpty ? '未绑定手机号' : _phone,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () async {
                  await storage.clear();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(builder: (_) => const LoginPage()),
                    (route) => false,
                  );
                },
                child: const Text('退出登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
