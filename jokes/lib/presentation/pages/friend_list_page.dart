import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/token_storage.dart';
import '../../data/models/chat_models.dart';
import '../../services/chat_realtime_service.dart';
import '../../services/friend_directory_service.dart';
import 'chat_detail_page.dart';

class FriendListPage extends StatefulWidget {
  const FriendListPage({super.key});

  @override
  State<FriendListPage> createState() => _FriendListPageState();
}

class _FriendListPageState extends State<FriendListPage> {
  late FriendDirectoryService _friendDirectoryService;
  ChatRealtimeService? _chatRealtimeService;
  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<PresenceEvent>? _presenceSub;
  StreamSubscription<TypingEvent>? _typingSub;
  bool _realtimeReady = false;
  String? _myId;

  late Future<List<Friend>> _friendsFuture;

  @override
  void initState() {
    super.initState();
    _friendsFuture = _loadFriends();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _friendDirectoryService = context.read<FriendDirectoryService>();
    if (_realtimeReady) return;

    final tokenStorage = context.read<TokenStorage>();
    final token = tokenStorage.getToken();
    _myId = tokenStorage.getPhone();
    final baseUrl = context.read<Dio>().options.baseUrl;
    if (token == null || token.isEmpty) return;

    _chatRealtimeService = ChatRealtimeService(apiBaseUrl: baseUrl, token: token);
    _realtimeReady = true;
    unawaited(_initRealtime());
  }

  Future<void> _initRealtime() async {
    final service = _chatRealtimeService;
    if (service == null) return;
    try {
      await service.connect();
      _messageSub = service.messages.listen((msg) {
        final myId = _myId;
        if (myId == null || myId.isEmpty) return;
        _friendDirectoryService.applyIncomingMessage(myId: myId, message: msg);
      });
      _presenceSub = service.presence.listen((event) {
        _friendDirectoryService.updatePresence(event.userId, event.online);
      });
      _typingSub = service.typing.listen((event) {
        _friendDirectoryService.updateTyping(event.fromUserId, event.isTyping);
      });
    } catch (_) {
      // Ignore realtime init failure, list still works via REST.
    }
  }

  Future<List<Friend>> _loadFriends({bool forceRefresh = false}) {
    return context.read<FriendDirectoryService>().loadFriends(
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _onRefresh() async {
    final next = _loadFriends(forceRefresh: true);
    setState(() {
      _friendsFuture = next;
    });
    await next;
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _presenceSub?.cancel();
    _typingSub?.cancel();
    _chatRealtimeService?.dispose();
    super.dispose();
  }

  void _showAddFriendSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddFriendSheet(
        service: context.read<FriendDirectoryService>(),
        onAdded: _onRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: '添加好友',
            onPressed: () => _showAddFriendSheet(context),
          ),
        ],
      ),
      body: FutureBuilder<List<Friend>>(
        future: _friendsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<List<Friend>>(
            stream: _friendDirectoryService.friendsStream,
            initialData: snapshot.data ?? const <Friend>[],
            builder: (context, streamSnapshot) {
              final friends = streamSnapshot.data ?? const <Friend>[];
              if (friends.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: ListView(
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text('暂无好友')),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _onRefresh,
                child: ListView.separated(
                  itemCount: friends.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    return _FriendTile(friend: friend);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.friend});

  final Friend friend;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: friend.avatarUrl.isNotEmpty
                ? NetworkImage(friend.avatarUrl)
                : null,
            child: friend.avatarUrl.isEmpty
                ? Text(
                    friend.name.isNotEmpty ? friend.name[0] : '?',
                    style: const TextStyle(fontSize: 18),
                  )
                : null,
          ),
          if (friend.unreadCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  friend.unreadCount > 99 ? '99+' : '${friend.unreadCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: friend.isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(friend.name),
      subtitle: (friend.isTyping ? '正在输入…' : friend.lastMessage).isNotEmpty
          ? Text(
              friend.isTyping ? '正在输入…' : friend.lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: friend.isTyping ? Colors.green : Colors.grey,
                fontStyle: friend.isTyping ? FontStyle.italic : FontStyle.normal,
              ),
            )
          : null,
      onTap: () {
        context.read<FriendDirectoryService>().markConversationReadLocal(friend.id);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatDetailPage(friend: friend),
          ),
        );
      },
    );
  }
}

// ─── Add Friend Bottom Sheet ───────────────────────────────────────────────

class _AddFriendSheet extends StatefulWidget {
  const _AddFriendSheet({required this.service, required this.onAdded});

  final FriendDirectoryService service;
  final Future<void> Function() onAdded;

  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
  final _phoneController = TextEditingController();
  bool _searching = false;
  bool _adding = false;
  Friend? _result;
  String? _errorMsg;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    setState(() {
      _searching = true;
      _result = null;
      _errorMsg = null;
    });
    final found = await widget.service.searchByPhone(phone);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _result = found;
      if (found == null) _errorMsg = '未找到该用户';
    });
  }

  Future<void> _add() async {
    if (_result == null) return;
    setState(() => _adding = true);
    final ok = await widget.service.addFriend(_result!.id);
    if (!mounted) return;
    setState(() => _adding = false);
    if (ok) {
      await widget.onAdded();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加好友')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('添加失败，可能已是好友')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('添加好友', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '请输入手机号',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _searching ? null : _search,
                child: _searching
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('搜索'),
              ),
            ],
          ),
          if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundImage: _result!.avatarUrl.isNotEmpty
                    ? NetworkImage(_result!.avatarUrl)
                    : null,
                child: _result!.avatarUrl.isEmpty
                    ? Text(_result!.name.isNotEmpty ? _result!.name[0] : '?')
                    : null,
              ),
              title: Text(_result!.name),
              subtitle: Text(_result!.id),
              trailing: ElevatedButton(
                onPressed: _adding ? null : _add,
                child: _adding
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('添加好友'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
