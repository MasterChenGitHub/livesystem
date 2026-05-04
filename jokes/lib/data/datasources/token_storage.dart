import 'package:hive/hive.dart';

const String tokenBoxName = 'auth_token_box';
const String _tokenKey = 'token';
const String _phoneKey = 'phone';
const String _nicknameKey = 'nickname';
const String _avatarKey = 'avatar';

class TokenStorage {
  TokenStorage(this._box);

  final Box<String> _box;

  /// Returns the persisted token, or null if not logged in.
  String? getToken() => _box.get(_tokenKey);

  /// Persists [token] to disk.
  Future<void> saveToken(String token) => _box.put(_tokenKey, token);

  /// Returns the persisted phone number.
  String? getPhone() => _box.get(_phoneKey);

  /// Persists [phone] to disk.
  Future<void> savePhone(String phone) => _box.put(_phoneKey, phone);

  /// Returns the persisted nickname.
  String? getNickname() => _box.get(_nicknameKey);

  /// Persists [nickname] to disk.
  Future<void> saveNickname(String nickname) => _box.put(_nicknameKey, nickname);

  /// Returns the persisted avatar URL.
  String? getAvatar() => _box.get(_avatarKey);

  /// Persists [avatar] to disk.
  Future<void> saveAvatar(String avatar) => _box.put(_avatarKey, avatar);

  /// Removes the token and phone (logout).
  Future<void> clear() async {
    await _box.delete(_tokenKey);
    await _box.delete(_phoneKey);
    await _box.delete(_nicknameKey);
    await _box.delete(_avatarKey);
  }

  /// True when a token is already stored.
  bool get hasToken {
    final t = getToken();
    return t != null && t.isNotEmpty;
  }
}
