import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum CallToneKind { voice, video }

class CallToneService {
  CallToneService._();

  static final CallToneService instance = CallToneService._();

  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _repeatTimer;
  static const String _outgoingTone = 'sounds/call_tone_outgoing.mp3';
  static const String _incomingTone = 'sounds/call_tone_incoming.mp3';
  static const String _connectedTone = 'sounds/call_tone_connected.mp3';
  static const String _hangupTone = 'sounds/call_tone_hangup.mp3';

  void stop() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _audioPlayer.stop();
  }

  void startOutgoing(CallToneKind kind) {
    stop();
    _playRepeating(_outgoingTone, const Duration(milliseconds: 1200));
  }

  void startIncoming(CallToneKind kind) {
    stop();
    _playRepeating(_incomingTone, const Duration(milliseconds: 1500));
  }

  void playConnected(CallToneKind kind) {
    stop();
    _playOnce(_connectedTone);
  }

  void playHangup(CallToneKind kind) {
    stop();
    _playOnce(_hangupTone);
  }

  Future<void> _playOnce(String assetPath) async {
    try {
      await _audioPlayer.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('[CallToneService] Error playing $assetPath: $e');
    }
  }

  void _playRepeating(String assetPath, Duration interval) async {
    try {
      await _audioPlayer.play(AssetSource(assetPath));
      _repeatTimer = Timer.periodic(interval, (_) async {
        if (_audioPlayer.state == PlayerState.playing) {
          return;
        }
        try {
          await _audioPlayer.play(AssetSource(assetPath));
        } catch (e) {
          debugPrint('[CallToneService] Error repeating $assetPath: $e');
        }
      });
    } catch (e) {
      debugPrint('[CallToneService] Error starting repeat for $assetPath: $e');
    }
  }

  void dispose() {
    stop();
    _audioPlayer.dispose();
  }
}
