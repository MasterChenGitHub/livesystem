import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/models/chat_models.dart';

class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({
    super.key,
    required this.friend,
    required this.callType,
  });

  final Friend friend;
  final String callType;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _previewStream;
  bool _rendererInitialized = false;
  bool _rendererReady = false;
  bool _previewReady = false;
  bool _disposed = false;
  bool _closing = false;

  bool get _isVideo => widget.callType == 'video';

  @override
  void initState() {
    super.initState();
    if (_isVideo) {
      _initPreview();
    }
  }

  Future<void> _initPreview() async {
    await _localRenderer.initialize();
    if (_disposed || !mounted) {
      await _localRenderer.dispose();
      return;
    }
    _rendererInitialized = true;
    _previewStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
        'frameRate': {'ideal': 24},
      },
    });
    if (_disposed || !mounted) {
      _previewStream?.getTracks().forEach((track) => track.stop());
      await _previewStream?.dispose();
      _previewStream = null;
      return;
    }
    _localRenderer.srcObject = _previewStream;
    setState(() {
      _rendererReady = true;
      _previewReady = _previewStream != null;
    });
  }

  Future<void> _disposePreview() async {
    if (_rendererInitialized) {
      try {
        _localRenderer.srcObject = null;
      } catch (_) {
        // Renderer may still be initializing or already disposed.
      }
    }
    _previewStream?.getTracks().forEach((track) => track.stop());
    await _previewStream?.dispose();
    _previewStream = null;
    _previewReady = false;
  }

  Future<void> _finish(bool accepted) async {
    if (_closing) return;
    _closing = true;
    await _disposePreview();
    if (!mounted) return;
    Navigator.of(context).pop(accepted);
  }

  @override
  void dispose() {
    _disposed = true;
    _disposePreview();
    if (_rendererInitialized) {
      _localRenderer.dispose();
      _rendererInitialized = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _isVideo;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: isVideo && _rendererReady && _previewReady
                  ? RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.grey.shade900,
                            Colors.black,
                          ],
                        ),
                      ),
                    ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isVideo
                      ? Colors.black.withAlpha(110)
                      : Colors.transparent,
                ),
              ),
            ),
            Positioned.fill(
              child: Column(
                children: [
                  const SizedBox(height: 56),
                  CircleAvatar(
                    radius: 52,
                    backgroundImage: widget.friend.avatarUrl.isNotEmpty
                        ? NetworkImage(widget.friend.avatarUrl)
                        : null,
                    child: widget.friend.avatarUrl.isEmpty
                        ? Text(
                            widget.friend.name.isNotEmpty
                                ? widget.friend.name[0]
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.friend.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isVideo ? '邀请你视频通话' : '邀请你语音通话',
                    style: TextStyle(
                      color: Colors.white.withAlpha(190),
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ActionButton(
                          icon: Icons.call_end,
                          label: '拒绝',
                          color: const Color(0xFFE53935),
                          onTap: () => _finish(false),
                        ),
                        _ActionButton(
                          icon: isVideo ? Icons.videocam : Icons.call,
                          label: '接听',
                          color: const Color(0xFF2E7D32),
                          onTap: () => _finish(true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 44),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
