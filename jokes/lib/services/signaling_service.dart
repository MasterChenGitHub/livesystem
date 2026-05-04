import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SignalingService {
  static const String _defaultWebrtcServerUrl = String.fromEnvironment(
    'WEBRTC_SERVER_URL',
    defaultValue: 'http://42.121.222.76',
  );

  SignalingService({
    required String myUserId,
    required String token,
    String? webrtcServerUrl,
  }) : _myUserId = myUserId,
       _token = token,
       _webrtcServerUrl = webrtcServerUrl ?? _defaultWebrtcServerUrl;

  final String _myUserId;
  final String _token;
  final String _webrtcServerUrl;

  WebSocket? _socket;
  String? _roomId;
  StreamSubscription<dynamic>? _socketSub;
  bool _disposed = false;
  Timer? _reconnectTimer;
  int _reconnectDelay = 2;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  String get myUserId => _myUserId;
  String? get roomId => _roomId;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  Future<void> connect({required String roomId}) async {
    if (_disposed) return;
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      if (_roomId == roomId) return;
      await joinRoom(roomId);
      return;
    }

    try {
      final wsUri = _buildWebSocketUri();
      _socket = await WebSocket.connect(wsUri.toString());
      _reconnectDelay = 2;
      _socketSub = _socket!.listen(
        _onSocketData,
        onDone: _onSocketDone,
        onError: (_) => _onSocketDone(),
        cancelOnError: false,
      );
      await joinRoom(roomId);
    } catch (_) {
      _onSocketDone();
    }
  }

  Future<void> joinRoom(String roomId) async {
    _roomId = roomId;
    await _send({'type': 'join', 'roomId': roomId});
  }

  Future<void> sendOffer(
    String toUserId,
    RTCSessionDescription sdp, {
    String callType = 'voice',
  }) => _send({
    'type': 'offer',
    'to': toUserId,
    'roomId': _roomId,
    'sdp': sdp.sdp,
    'callType': callType,
  });

  Future<void> sendAnswer(String toUserId, RTCSessionDescription sdp) => _send({
    'type': 'answer',
    'to': toUserId,
    'roomId': _roomId,
    'sdp': sdp.sdp,
  });

  Future<void> sendIce(String toUserId, RTCIceCandidate candidate) => _send({
    'type': 'ice-candidate',
    'to': toUserId,
    'roomId': _roomId,
    'candidate': candidate.candidate,
    'sdpMid': candidate.sdpMid,
    'sdpMLineIndex': candidate.sdpMLineIndex,
  });

  Future<void> sendHangup(String toUserId) =>
      _send({'type': 'hangup', 'to': toUserId, 'roomId': _roomId});

  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    final dioForWebrtc = Dio()..options.baseUrl = _webrtcServerUrl;
    final response = await dioForWebrtc.get<dynamic>('/api/webrtc/config');
    final body = response.data;
    final data = body is Map<String, dynamic>
        ? (body['data'] as Map<String, dynamic>? ?? body)
        : null;

    final iceServers = data?['iceServers'];
    if (iceServers is List) {
      return iceServers.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _roomId = null; // 先置空，防止 _onSocketDone 触发重连
    await _send({'type': 'leave', 'roomId': _roomId});
    await _socketSub?.cancel();
    await _socket?.close();
    _socketSub = null;
    _socket = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await disconnect();
    await _messageController.close();
  }

  Uri _buildWebSocketUri() {
    final baseUri = Uri.parse(_webrtcServerUrl);
    return Uri(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '/ws/signaling',
      queryParameters: {'token': _token, 'userId': _myUserId},
    );
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode(payload));
  }

  void _onSocketData(dynamic data) {
    if (data is! String) return;
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) {
      _messageController.add(decoded);
    }
  }

  void _onSocketDone() {
    _socketSub?.cancel();
    _socketSub = null;
    _socket = null;
    // 通话结束后不需要重连（roomId 为 null 表示已主动断开）
    if (_disposed || _roomId == null) return;
    final roomToReconnect = _roomId!;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () async {
      _reconnectDelay = (_reconnectDelay * 2).clamp(2, 30);
      await connect(roomId: roomToReconnect);
    });
  }
}
