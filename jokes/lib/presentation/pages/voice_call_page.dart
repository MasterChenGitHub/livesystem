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

class VoiceCallPage extends StatefulWidget {
  const VoiceCallPage({
    super.key,
    required this.friend,
    this.incomingOfferSdp,
    this.incomingRoomId,
  });

  final Friend friend;
  final String? incomingOfferSdp;
  final String? incomingRoomId;

  @override
  State<VoiceCallPage> createState() => _VoiceCallPageState();
}

class _VoiceCallPageState extends State<VoiceCallPage> {
  WebRTCCallCubit? _callCubit;
  bool _initialized = false;
  bool _didPop = false;
  bool _callRecordSent = false;
  MessageService? _messageService;
  String _myUserId = '';
  final RTCVideoRenderer _remoteAudioRenderer = RTCVideoRenderer();
  bool _rendererReady = false;
  String? _boundRemoteStreamId;
  final _toneService = CallToneService.instance;
  WebRTCCallState _lastCallState = WebRTCCallState.idle;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _remoteAudioRenderer.initialize();
    if (!mounted) return;
    setState(() {
      _rendererReady = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final storage = context.read<TokenStorage>();
      final token = storage.getToken();
      final myUserId = storage.getPhone() ?? '';
      _myUserId = myUserId;
      if (token == null || token.isEmpty || myUserId.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请先登录后再发起通话')));
          Navigator.of(context).pop();
        });
        _initialized = true;
        return;
      }

      _messageService = MessageService(
        dio: context.read<Dio>(),
        tokenStorage: storage,
      );

      final signaling = SignalingService(
        myUserId: myUserId,
        token: token,
      );
      _callCubit = WebRTCCallCubit(
        signaling,
        enableVideo: false,
        callType: 'voice',
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
          _toneService.startOutgoing(CallToneKind.voice);
          _callCubit?.startCall(widget.friend.id);
        }
      });
    }
  }

  Future<void> _sendVoiceCallRecord(WebRTCCallStatus status) async {
    if (_callRecordSent) return;
    if (widget.incomingOfferSdp != null) return; // caller side only
    if (status.durationSeconds <= 0) return;

    final service = _messageService;
    if (service == null) return;

    _callRecordSent = true;
    final content = '📞 语音通话 ${status.formattedDuration}';
    try {
      final sent = await service.sendMessage(
        receiverPhone: widget.friend.id,
        content: content,
        type: 'voice',
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

  @override
  void dispose() {
    _toneService.stop();
    _remoteAudioRenderer.srcObject = null;
    _remoteAudioRenderer.dispose();
    _callCubit?.close();
    super.dispose();
  }

  void _bindRemoteAudioStream() {
    final cubit = _callCubit;
    if (!_rendererReady || cubit == null) {
      return;
    }

    final stream = cubit.remoteStream;
    final streamId = stream?.id;
    if (_boundRemoteStreamId == streamId) {
      return;
    }

    _remoteAudioRenderer.srcObject = stream;
    _boundRemoteStreamId = streamId;
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
            _toneService.playConnected(CallToneKind.voice);
          } else if (status.state == WebRTCCallState.ended &&
              _lastCallState != WebRTCCallState.ended) {
            _toneService.playHangup(CallToneKind.voice);
          }
          _lastCallState = status.state;
          final shouldAutoClose =
              status.state == WebRTCCallState.ended &&
              status.errorMessage == null;
          if (shouldAutoClose) {
            unawaited(_sendVoiceCallRecord(status));
            Future<void>.delayed(const Duration(milliseconds: 220), () {
              if (!mounted) return;
              _popIfNeeded();
            });
          }
        },
        builder: (context, status) {
          _bindRemoteAudioStream();
          final colorScheme = Theme.of(context).colorScheme;

          final String statusText;
          switch (status.state) {
            case WebRTCCallState.calling:
              statusText = widget.incomingOfferSdp != null ? '正在接听…' : '正在呼叫…';
            case WebRTCCallState.ringing:
              statusText = '对方正在响铃…';
            case WebRTCCallState.inCall:
              statusText = status.formattedDuration;
            case WebRTCCallState.ended:
              statusText = '通话已结束';
            case WebRTCCallState.idle:
              statusText = '';
          }

          return Scaffold(
            backgroundColor: colorScheme.inverseSurface,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxHeight < 600;
                  final avatarRadius = isCompact ? 36.0 : 50.0;
                  final avatarFontSize = isCompact ? 26.0 : 36.0;
                  final nameFontSize = isCompact ? 20.0 : 26.0;
                  final horizontalGap = isCompact ? 20.0 : 40.0;

                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            SizedBox(
                              width: 1,
                              height: 1,
                              child: RTCVideoView(_remoteAudioRenderer),
                            ),
                            // ── Caller info ──────────────────────────────
                            Padding(
                              padding: EdgeInsets.only(
                                top: isCompact ? 20.0 : 48.0,
                              ),
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: avatarRadius,
                                    backgroundImage:
                                        widget.friend.avatarUrl.isNotEmpty
                                        ? NetworkImage(widget.friend.avatarUrl)
                                        : null,
                                    child: widget.friend.avatarUrl.isEmpty
                                        ? Text(
                                            widget.friend.name.isNotEmpty
                                                ? widget.friend.name[0]
                                                : '?',
                                            style: TextStyle(
                                              fontSize: avatarFontSize,
                                              color:
                                                  colorScheme.onInverseSurface,
                                            ),
                                          )
                                        : null,
                                  ),
                                  SizedBox(height: isCompact ? 10 : 20),
                                  Text(
                                    widget.friend.name,
                                    style: TextStyle(
                                      fontSize: nameFontSize,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onInverseSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: colorScheme.onInverseSurface
                                          .withAlpha(180),
                                    ),
                                  ),
                                  if (status.errorMessage != null) ...[
                                    const SizedBox(height: 6),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                      child: Text(
                                        status.errorMessage!,
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const Spacer(),

                            // ── Controls ─────────────────────────────────
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: isCompact ? 20.0 : 48.0,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _ToggleButton(
                                        icon: status.isMuted
                                            ? Icons.mic_off
                                            : Icons.mic,
                                        label: status.isMuted ? '已静音' : '麦克风',
                                        active: status.isMuted,
                                        onTap: callCubit.toggleMute,
                                      ),
                                      SizedBox(width: horizontalGap),
                                      _ToggleButton(
                                        icon: status.isSpeakerOn
                                            ? Icons.volume_up
                                            : Icons.volume_down,
                                        label: status.isSpeakerOn
                                            ? '扬声器'
                                            : '听筒',
                                        active: status.isSpeakerOn,
                                        onTap: callCubit.toggleSpeaker,
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: isCompact ? 20.0 : 32.0),
                                  GestureDetector(
                                    onTap: _hangUp,
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.call_end,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? Colors.white.withAlpha(60) : Colors.white.withAlpha(30);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
