import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/models/chat_models.dart';

class PresenceEvent {
  const PresenceEvent({required this.userId, required this.online});

  final String userId;
  final bool online;
}

class TypingEvent {
  const TypingEvent({required this.fromUserId, required this.isTyping});

  final String fromUserId;
  final bool isTyping;
}

class ReadReceiptEvent {
  const ReadReceiptEvent({required this.readerId});

  final String readerId;
}

class ChatRealtimeService {
  ChatRealtimeService({
    required String apiBaseUrl,
    required String token,
  }) : _apiBaseUrl = apiBaseUrl,
       _token = token;

  final String _apiBaseUrl;
  final String _token;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;
  Timer? _reconnectTimer;
  int _reconnectDelay = 2;

  final StreamController<ChatMessage> _messagesController =
      StreamController<ChatMessage>.broadcast();
  final StreamController<PresenceEvent> _presenceController =
      StreamController<PresenceEvent>.broadcast();
  final StreamController<TypingEvent> _typingController =
      StreamController<TypingEvent>.broadcast();
  final StreamController<ReadReceiptEvent> _readController =
      StreamController<ReadReceiptEvent>.broadcast();

  Stream<ChatMessage> get messages => _messagesController.stream;
  Stream<PresenceEvent> get presence => _presenceController.stream;
  Stream<TypingEvent> get typing => _typingController.stream;
  Stream<ReadReceiptEvent> get readReceipts => _readController.stream;

  Future<void> connect() async {
    if (_disposed) return;
    if (_socket != null && _socket!.readyState == WebSocket.open) return;

    try {
      final uri = _buildWebSocketUri();
      _socket = await WebSocket.connect(uri.toString());
      _reconnectDelay = 2; // 连接成功后重置退避时间
      _sub = _socket!.listen(
        _onData,
        onError: (_) => _onDisconnected(),
        onDone: _onDisconnected,
        cancelOnError: false,
      );
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    _cleanupSocket();
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () async {
      _reconnectDelay = (_reconnectDelay * 2).clamp(2, 30);
      await connect();
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    await _socket?.close();
    _cleanupSocket();
    await _messagesController.close();
    await _presenceController.close();
    await _typingController.close();
    await _readController.close();
  }

  void sendTyping({required String toUserId, required bool isTyping}) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(
      jsonEncode({
        'type': 'typing',
        'to': toUserId,
        'isTyping': isTyping,
      }),
    );
  }

  Uri _buildWebSocketUri() {
    final base = Uri.parse(_apiBaseUrl);
    return Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/ws/chat',
      queryParameters: {'token': _token},
    );
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return;

    final type = decoded['type']?.toString();
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) return;

    switch (type) {
      case 'chat-message':
        _messagesController.add(
          ChatMessage(
            id: (data['id'] ?? '').toString(),
            senderId: (data['senderPhone'] ?? '').toString(),
            receiverId: (data['receiverPhone'] ?? '').toString(),
            content: (data['content'] ?? '').toString(),
            type: _parseType((data['type'] ?? 'text').toString()),
            createdAt: data['createdAt'] != null
                ? DateTime.parse(data['createdAt'].toString())
                : DateTime.now(),
            imageUrl: data['imageUrl']?.toString(),
            thumbUrl: data['thumbUrl']?.toString(),
            imageWidth: int.tryParse((data['imageWidth'] ?? '').toString()),
            imageHeight: int.tryParse((data['imageHeight'] ?? '').toString()),
            imageSize: int.tryParse((data['imageSize'] ?? '').toString()),
            videoUrl: data['videoUrl']?.toString(),
            videoThumbUrl: data['videoThumbUrl']?.toString(),
            videoDuration: int.tryParse((data['videoDuration'] ?? '').toString()),
            videoWidth: int.tryParse((data['videoWidth'] ?? '').toString()),
            videoHeight: int.tryParse((data['videoHeight'] ?? '').toString()),
            voiceUrl: data['voiceUrl']?.toString(),
            voiceDuration: int.tryParse((data['voiceDuration'] ?? '').toString()),
            isRead: data['read'] == true,
          ),
        );
        break;
      case 'presence':
        _presenceController.add(
          PresenceEvent(
            userId: (data['userId'] ?? '').toString(),
            online: data['online'] == true,
          ),
        );
        break;
      case 'typing':
        _typingController.add(
          TypingEvent(
            fromUserId: (data['fromUserId'] ?? '').toString(),
            isTyping: data['isTyping'] == true,
          ),
        );
        break;
      case 'chat-read':
        _readController.add(
          ReadReceiptEvent(readerId: (data['readerId'] ?? '').toString()),
        );
        break;
      default:
        break;
    }
  }

  MessageType _parseType(String type) {
    switch (type.toLowerCase()) {
      case 'image':
        return MessageType.image;
      case 'video':
        return MessageType.video;
      case 'voice':
        return MessageType.voice;
      default:
        return MessageType.text;
    }
  }

  void _cleanupSocket() {
    _sub?.cancel();
    _sub = null;
    _socket = null;
  }
}
