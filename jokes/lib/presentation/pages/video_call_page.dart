import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/datasources/token_storage.dart';
import '../../data/models/chat_models.dart';
import '../../services/call_tone_service.dart';
import '../../services/friend_directory_service.dart';
import '../../services/message_service.dart';
import '../../services/signaling_service.dart';
import '../../services/webrtc_call_service.dart';

class VideoCallPage extends StatefulWidget {
  const VideoCallPage({
    super.key,
    required this.friend,
    this.incomingOfferSdp,
    this.incomingRoomId,
  });

  final Friend friend;
  final String? incomingOfferSdp;
  final String? incomingRoomId;

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  WebRTCCallCubit? _callCubit;
  bool _initialized = false;
  bool _didPop = false;
  bool _callRecordSent = false;
  MessageService? _messageService;
  String _myUserId = '';
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _rendererReady = false;
  bool _swapped = false;
  String? _boundRemoteId;
  String? _boundLocalId;
  final _toneService = CallToneService.instance;
  WebRTCCallState _lastCallState = WebRTCCallState.idle;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _remoteRenderer.initialize();
    await _localRenderer.initialize();
    if (!mounted) return;
    setState(() {
      _rendererReady = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    final storage = context.read<TokenStorage>();
    final token = storage.getToken();
    final myUserId = storage.getPhone() ?? '';
    _myUserId = myUserId;
    if (token == null || token.isEmpty || myUserId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先登录后再发起视频通话')));
        Navigator.of(context).pop();
      });
      _initialized = true;
      return;
    }

    _messageService = MessageService(
      dio: context.read<Dio>(),
      tokenStorage: storage,
    );

    final signaling = SignalingService(myUserId: myUserId, token: token);
    _callCubit = WebRTCCallCubit(
      signaling,
      enableVideo: true,
      callType: 'video',
    );
    _initialized = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final offerSdp = widget.incomingOfferSdp;
      if (offerSdp != null && offerSdp.isNotEmpty) {
        _callCubit?.handleOffer(
          widget.friend.id,
          RTCSessionDescription(offerSdp, 'offer'),
          roomId: widget.incomingRoomId,
        );
      } else {
        _toneService.startOutgoing(CallToneKind.video);
        _callCubit?.startCall(widget.friend.id);
      }
    });
  }

  Future<void> _sendVideoCallRecord(WebRTCCallStatus status) async {
    if (_callRecordSent) return;
    if (widget.incomingOfferSdp != null) return; // caller side only
    if (status.durationSeconds <= 0) return;

    final service = _messageService;
    if (service == null) return;

    _callRecordSent = true;
    final content = '📹 视频通话 ${status.formattedDuration}';
    try {
      final sent = await service.sendMessage(
        receiverPhone: widget.friend.id,
        content: content,
        type: 'video',
      );
      if (!mounted || sent == null) return;
      context.read<FriendDirectoryService>().applyIncomingMessage(
        myId: _myUserId,
        message: sent,
      );
    } catch (_) {
      // Keep call flow smooth even if record persistence fails.
    }
  }

  void _bindStreams() {
    final cubit = _callCubit;
    if (!_rendererReady || cubit == null) return;

    final remote = cubit.remoteStream;
    final local = cubit.localStream;

    if (_boundRemoteId != remote?.id) {
      _remoteRenderer.srcObject = remote;
      _boundRemoteId = remote?.id;
    }

    if (_boundLocalId != local?.id) {
      _localRenderer.srcObject = local;
      _boundLocalId = local?.id;
    }
  }

  Future<void> _hangUp() async {
    await _callCubit?.hangUp();
  }

  void _popIfNeeded() {
    if (!mounted || _didPop) return;
    _didPop = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _toneService.stop();
    _remoteRenderer.srcObject = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    _callCubit?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callCubit = _callCubit;
    if (callCubit == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BlocProvider.value(
      value: callCubit,
      child: BlocConsumer<WebRTCCallCubit, WebRTCCallStatus>(
        listener: (context, status) {
          if (status.state == WebRTCCallState.inCall &&
              _lastCallState != WebRTCCallState.inCall) {
            _toneService.playConnected(CallToneKind.video);
          } else if (status.state == WebRTCCallState.ended &&
              _lastCallState != WebRTCCallState.ended) {
            _toneService.playHangup(CallToneKind.video);
          }
          _lastCallState = status.state;
          if (status.state == WebRTCCallState.ended && mounted && !_didPop) {
            unawaited(_sendVideoCallRecord(status));
            Future<void>.delayed(const Duration(milliseconds: 220), () {
              if (!mounted) return;
              _popIfNeeded();
            });
          }
        },
        builder: (context, status) {
          _bindStreams();
          final statusText = switch (status.state) {
            WebRTCCallState.calling => '正在呼叫视频…',
            WebRTCCallState.ringing => '对方正在响铃…',
            WebRTCCallState.inCall => status.formattedDuration,
            WebRTCCallState.ended => '通话已结束',
            WebRTCCallState.idle => '',
          };

          return Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Positioned.fill(
                  child: _rendererReady && (_swapped ? _boundLocalId != null : _boundRemoteId != null)
                      ? RTCVideoView(
                          _swapped ? _localRenderer : _remoteRenderer,
                          mirror: _swapped,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : Container(
                          color: Colors.black,
                          alignment: Alignment.center,
                          child: Text(
                            statusText,
                            style: const TextStyle(color: Colors.white70, fontSize: 18),
                          ),
                        ),
                ),
                Positioned(
                  top: 56,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      Text(
                        widget.friend.name,
                        style: const TextStyle(color: Colors.white, fontSize: 22),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        statusText,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (status.errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          status.errorMessage!,
                          style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  top: 56,
                  right: 16,
                  child: GestureDetector(
                    onTap: () => setState(() => _swapped = !_swapped),
                    child: Container(
                      width: 110,
                      height: 160,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _rendererReady && (_swapped ? _boundRemoteId != null : _boundLocalId != null)
                          ? RTCVideoView(
                              _swapped ? _remoteRenderer : _localRenderer,
                              mirror: !_swapped,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            )
                          : const Center(
                              child: Icon(Icons.videocam, color: Colors.white70),
                            ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CircleButton(
                        icon: status.isMuted ? Icons.mic_off : Icons.mic,
                        onTap: callCubit.toggleMute,
                      ),
                      const SizedBox(width: 20),
                      _CircleButton(
                        icon: status.isCameraOn ? Icons.videocam : Icons.videocam_off,
                        onTap: callCubit.toggleCamera,
                      ),
                      const SizedBox(width: 20),
                      _CircleButton(
                        icon: Icons.flip_camera_ios,
                        onTap: callCubit.switchCamera,
                      ),
                      const SizedBox(width: 20),
                      _CircleButton(
                        icon: Icons.call_end,
                        color: Colors.red,
                        onTap: _hangUp,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.color = const Color(0x55FFFFFF),
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
