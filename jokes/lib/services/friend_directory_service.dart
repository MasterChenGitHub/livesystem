import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '../data/datasources/token_storage.dart';
import '../data/mock/mock_friends.dart';
import '../data/models/chat_models.dart';

const String friendCacheBoxName = 'friend_cache_box';
const String _friendsCacheKey = 'friends_json';

class FriendDirectoryService {
  FriendDirectoryService({
    required Dio dio,
    required TokenStorage tokenStorage,
    required Box<String> cacheBox,
  }) : _dio = dio,
       _tokenStorage = tokenStorage,
       _cacheBox = cacheBox;

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final Box<String> _cacheBox;
  final StreamController<List<Friend>> _friendsController =
      StreamController<List<Friend>>.broadcast();

  List<Friend> _friends = const [];

  List<Friend> get currentFriends => _friends;
  Stream<List<Friend>> get friendsStream => _friendsController.stream;

  Future<List<Friend>> loadFriends({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _readCache();
      if (cached.isNotEmpty) {
        _friends = cached;
        _sortFriends();
        updateResolvedFriends(cached);
        _emit();
      }
    }

    final token = _tokenStorage.getToken();
    if (token == null || token.isEmpty) {
      return _friends;
    }

    try {
      final response = await _dio.get<dynamic>('/friends/list');

      final parsed = _parseFriends(response.data);
      if (parsed.isNotEmpty || _friends.isEmpty) {
        _friends = parsed;
        _sortFriends();
        updateResolvedFriends(_friends);
        await _writeCache(_friends);
        _emit();
      }
    } catch (_) {
      // Keep cached friends when API fails.
    }

    return _friends;
  }

  /// Search a user by exact phone number. Returns null if not found.
  Future<Friend?> searchByPhone(String phone) async {
    try {
      final response = await _dio.get<dynamic>(
        '/friends/search',
        queryParameters: {'phone': phone},
      );
      final body = response.data;
      dynamic data = body is Map<String, dynamic> ? (body['data'] ?? body) : body;
      if (data is Map<String, dynamic>) {
        return _mapToFriend(data);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
    } catch (_) {}
    return null;
  }

  /// Send an add-friend request. Returns true on success.
  Future<bool> addFriend(String targetPhone) async {
    try {
      final response = await _dio.post<dynamic>(
        '/friends/add',
        data: {'phone': targetPhone},
      );
      final code = (response.data as Map<String, dynamic>?)?['code'];
      if (code != 200) return false;

      // Auto-refresh list immediately after successful add.
      await loadFriends(forceRefresh: true);

      // Fallback: if backend list is not immediately updated, optimistically add.
      if (_friends.every((f) => f.id != targetPhone)) {
        final found = await searchByPhone(targetPhone);
        if (found != null) {
          _friends = [
            found.copyWith(lastMessageTime: DateTime.now()),
            ..._friends,
          ];
          _sortFriends();
          _emit();
          await _writeCache(_friends);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearCache() async {
    _friends = const [];
    updateResolvedFriends(const []);
    await _cacheBox.delete(_friendsCacheKey);
    _emit();
  }

  Future<void> dispose() async {
    await _friendsController.close();
  }

  void applyIncomingMessage({
    required String myId,
    required ChatMessage message,
  }) {
    final friendId =
        message.senderId == myId ? (message.receiverId ?? '') : message.senderId;
    if (friendId.isEmpty) return;

    _friends = _friends.map((f) {
      if (f.id != friendId) return f;
      final nextUnread = message.senderId == myId ? f.unreadCount : f.unreadCount + 1;
      final lastMessagePreview = switch (message.type) {
        MessageType.text => message.content,
        MessageType.image => '[图片]',
        MessageType.video => '[视频]',
        MessageType.voice => message.content.isNotEmpty ? message.content : '[语音通话]',
      };
      return f.copyWith(
        lastMessage: lastMessagePreview,
        lastMessageTime: message.createdAt,
        unreadCount: nextUnread,
        isTyping: false,
      );
    }).toList(growable: false);
    _sortFriends();
    _emit();
    unawaited(_writeCache(_friends));
  }

  void markConversationReadLocal(String friendId) {
    _friends = _friends
        .map((f) => f.id == friendId ? f.copyWith(unreadCount: 0, isTyping: false) : f)
        .toList(growable: false);
    _emit();
    unawaited(_writeCache(_friends));
  }

  void updatePresence(String friendId, bool isOnline) {
    _friends = _friends
        .map((f) => f.id == friendId ? f.copyWith(isOnline: isOnline) : f)
        .toList(growable: false);
    _emit();
  }

  void updateTyping(String friendId, bool isTyping) {
    _friends = _friends
        .map((f) => f.id == friendId ? f.copyWith(isTyping: isTyping) : f)
        .toList(growable: false);
    _emit();
  }

  void _sortFriends() {
    final next = [..._friends];
    next.sort((a, b) {
      final at = a.lastMessageTime;
      final bt = b.lastMessageTime;
      if (at == null && bt == null) return a.name.compareTo(b.name);
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    _friends = List<Friend>.unmodifiable(next);
  }

  void _emit() {
    updateResolvedFriends(_friends);
    _friendsController.add(_friends);
  }

  List<Friend> _readCache() {
    final raw = _cacheBox.get(_friendsCacheKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(_mapToFriend)
            .toList(growable: false);
      }
    } catch (_) {
      // Ignore bad cache payload.
    }
    return const [];
  }

  Future<void> _writeCache(List<Friend> friends) async {
    final payload = friends
        .map(
          (f) => {
            'id': f.id,
            'name': f.name,
            'avatarUrl': f.avatarUrl,
            'lastMessage': f.lastMessage,
            'lastMessageTime': f.lastMessageTime?.toIso8601String(),
            'unreadCount': f.unreadCount,
            'isOnline': f.isOnline,
            'isTyping': f.isTyping,
          },
        )
        .toList(growable: false);
    await _cacheBox.put(_friendsCacheKey, jsonEncode(payload));
  }

  List<Friend> _parseFriends(dynamic rawBody) {
    dynamic data = rawBody;
    if (rawBody is Map<String, dynamic>) {
      data = rawBody['data'] ?? rawBody;
    }

    if (data is List) {
      return data.whereType<Map<String, dynamic>>().map(_mapToFriend).toList();
    }
    return const [];
  }

  Friend _mapToFriend(Map<String, dynamic> json) {
    return Friend(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      lastMessage: json['lastMessage']?.toString() ?? '',
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.tryParse(json['lastMessageTime'].toString())
          : null,
      unreadCount: int.tryParse(json['unreadCount']?.toString() ?? '') ?? 0,
      isOnline: json['isOnline'] == true,
      isTyping: json['isTyping'] == true,
    );
  }
}
