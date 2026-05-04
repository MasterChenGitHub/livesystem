import '../models/chat_models.dart';

const List<Friend> mockFriends = [
  Friend(
    id: 'u1',
    name: '张三',
    avatarUrl: '',
    lastMessage: '你好呀！',
    unreadCount: 2,
  ),
  Friend(
    id: 'u2',
    name: '李四',
    avatarUrl: '',
    lastMessage: '明天有空吗？',
    unreadCount: 0,
  ),
  Friend(
    id: 'u3',
    name: '王五',
    avatarUrl: '',
    lastMessage: '哈哈哈',
    unreadCount: 1,
  ),
];

List<Friend> _resolvedFriends = mockFriends;

List<Friend> get resolvedFriends => _resolvedFriends;

void updateResolvedFriends(List<Friend> friends) {
  if (friends.isEmpty) {
    _resolvedFriends = mockFriends;
    return;
  }
  _resolvedFriends = List<Friend>.unmodifiable(friends);
}

Friend resolveIncomingFriend(String fromUserId) {
  final known = _resolvedFriends.where((f) => f.id == fromUserId).firstOrNull;
  if (known != null) {
    return known;
  }

  final phoneRegex = RegExp(r'^1\d{10}$');
  final fallbackName = phoneRegex.hasMatch(fromUserId)
      ? '用户${fromUserId.substring(fromUserId.length - 4)}'
      : fromUserId;
  return Friend(id: fromUserId, name: fallbackName);
}
