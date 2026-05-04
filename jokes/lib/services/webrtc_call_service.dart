import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'signaling_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum WebRTCCallState { idle, calling, ringing, inCall, ended }

class WebRTCCallStatus {
  const WebRTCCallStatus({
    this.state = WebRTCCallState.idle,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isCameraOn = true,
    this.durationSeconds = 0,
    this.errorMessage,
  });

  final WebRTCCallState state;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isCameraOn;
  final int durationSeconds;
  final String? errorMessage;

  bool get isActive =>
      state == WebRTCCallState.inCall || state == WebRTCCallState.calling;

  String get formattedDuration {
    final m = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  WebRTCCallStatus copyWith({
    WebRTCCallState? state,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isCameraOn,
    int? durationSeconds,
    Object? errorMessage = _sentinel,
  }) {
    return WebRTCCallStatus(
      state: state ?? this.state,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const _sentinel = Object();

// ---------------------------------------------------------------------------
// WebRTC configuration
// ---------------------------------------------------------------------------

Map<String, dynamic> _fallbackRtcConfig() {
  return {
    'iceServers': [
      {'urls': 'stun:stun.qq.com:3478'},
      {'urls': 'stun:stun.miwifi.com:3478'},
    ],
  };
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class WebRTCCallCubit extends Cubit<WebRTCCallStatus> {
  WebRTCCallCubit(
    this._signaling, {
    bool enableVideo = false,
    String callType = 'voice',
  }) : _enableVideo = enableVideo,
       _callType = callType,
       super(WebRTCCallStatus(isCameraOn: enableVideo));

  final SignalingService _signaling;
  final bool _enableVideo;
  final String _callType;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  Timer? _durationTimer;
  Timer? _statsLogTimer;
  StreamSubscription<Map<String, dynamic>>? _signalSub;
  String? _activeRemoteUserId;
  String? _activeRoomId;
  bool _hangingUp = false;
  bool _remoteDescriptionReady = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  Timer? _iceDisconnectTimer;
  Completer<void>? _iceGatheringCompleter;
  final bool _useTrickleIce = true;
  final bool _forceRelayCandidatesOnly = false;
  int _localCandidateCount = 0;
  int _remoteCandidateReceivedCount = 0;
  int _remoteCandidateAppliedCount = 0;
  int _remoteAudioTrackCount = 0;

  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;
  bool get enableVideo => _enableVideo;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Start an outgoing call to [remoteUserId].
  Future<void> startCall(String remoteUserId) async {
    if (state.isActive) {
      return;
    }
    if (!isClosed) {
      emit(state.copyWith(state: WebRTCCallState.calling));
    }

    try {
      _remoteDescriptionReady = false;
      _pendingRemoteCandidates.clear();
      _resetDiagnostics();
      _activeRemoteUserId = remoteUserId;
      _activeRoomId = _buildRoomId(_signaling.myUserId, remoteUserId);
      _log('startCall remote=$remoteUserId room=$_activeRoomId');
      await _ensureSignalingConnected(remoteUserId, roomId: _activeRoomId);
      await _initPeerConnection(remoteUserId);
      await _getLocalAudio();
      await _prepareAudioRouting();

      final offer = await _peerConnection!.createOffer(_buildSdpConstraints());
      _log('offer created, sdpLen=${offer.sdp?.length ?? 0}');
      await _peerConnection!.setLocalDescription(offer);
      _log('offer set as local description, waiting for candidates...');
      if (_useTrickleIce) {
        final outboundOffer = _forceRelayCandidatesOnly
            ? _stripNonRelayCandidatesFromSdp(offer)
            : offer;
        _log('sending trickle offer immediately, localCandidates=$_localCandidateCount');
        await _signaling.sendOffer(
          remoteUserId,
          outboundOffer,
          callType: _callType,
        );
      } else {
        await _waitForIceGatheringComplete();
        final finalOffer = await _peerConnection!.getLocalDescription();
        final offerToSend = finalOffer ?? offer;
        final outboundOffer = _forceRelayCandidatesOnly
            ? _stripNonRelayCandidatesFromSdp(offerToSend)
            : offerToSend;
        await _signaling.sendOffer(
          remoteUserId,
          outboundOffer,
          callType: _callType,
        );
      }
    } catch (e) {
      _log('startCall error=$e');
      if (!isClosed) {
        emit(
          state.copyWith(
            state: WebRTCCallState.ended,
            errorMessage: e.toString(),
          ),
        );
      }
      await _cleanup();
    }
  }

  /// Handle an incoming call (call with the received offer SDP).
  Future<void> handleOffer(
    String remoteUserId,
    RTCSessionDescription offer, {
    String? roomId,
  }) async {
    if (!isClosed) {
      emit(state.copyWith(state: WebRTCCallState.ringing));
    }

    try {
      _remoteDescriptionReady = false;
      _pendingRemoteCandidates.clear();
      _resetDiagnostics();
      _activeRemoteUserId = remoteUserId;
      _activeRoomId = roomId ?? _buildRoomId(_signaling.myUserId, remoteUserId);
      _log('handleOffer from=$remoteUserId room=$_activeRoomId');
      await _ensureSignalingConnected(remoteUserId, roomId: _activeRoomId);
      await _initPeerConnection(remoteUserId);
      await _setRemoteDescription(offer);
      await _getLocalAudio();
      await _prepareAudioRouting();

      final answer = await _peerConnection!.createAnswer(_buildSdpConstraints());
      _log('answer created, sdpLen=${answer.sdp?.length ?? 0}');
      await _peerConnection!.setLocalDescription(answer);
      _log('answer set as local description, waiting for candidates...');
      if (_useTrickleIce) {
        final outboundAnswer = _forceRelayCandidatesOnly
            ? _stripNonRelayCandidatesFromSdp(answer)
            : answer;
        _log('sending trickle answer immediately, localCandidates=$_localCandidateCount');
        await _signaling.sendAnswer(remoteUserId, outboundAnswer);
      } else {
        await _waitForIceGatheringComplete();
        final finalAnswer = await _peerConnection!.getLocalDescription();
        final answerToSend = finalAnswer ?? answer;
        final outboundAnswer = _forceRelayCandidatesOnly
            ? _stripNonRelayCandidatesFromSdp(answerToSend)
            : answerToSend;
        await _signaling.sendAnswer(remoteUserId, outboundAnswer);
      }

      if (!isClosed) {
        emit(state.copyWith(state: WebRTCCallState.inCall));
      }
      _startDurationTimer();
    } catch (e) {
      _log('handleOffer error=$e');
      if (!isClosed) {
        emit(
          state.copyWith(
            state: WebRTCCallState.ended,
            errorMessage: e.toString(),
          ),
        );
      }
      await _cleanup();
    }
  }

  Future<void> hangUp() async {
    if (_hangingUp) return;
    _hangingUp = true;

    final remoteId = _activeRemoteUserId;
    _log('hangUp remote=$remoteId room=$_activeRoomId');
    if (remoteId != null) {
      await _signaling.sendHangup(remoteId);
    }

    _durationTimer?.cancel();
    await _signalSub?.cancel();
    _signalSub = null;
    if (!isClosed) emit(state.copyWith(state: WebRTCCallState.ended));
    await _cleanup();
    await _signaling.disconnect();
    _activeRemoteUserId = null;
    _hangingUp = false;
  }

  Future<void> toggleMute() async {
    final muted = !state.isMuted;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !muted;
    });
    if (!isClosed) emit(state.copyWith(isMuted: muted));
  }

  Future<void> toggleSpeaker() async {
    final speakerOn = !state.isSpeakerOn;
    await Helper.setSpeakerphoneOn(speakerOn);
    await _selectPreferredAudioOutput(speakerOn: speakerOn);
    if (!isClosed) emit(state.copyWith(isSpeakerOn: speakerOn));
  }

  Future<void> toggleCamera() async {
    if (!_enableVideo) return;
    final cameraOn = !state.isCameraOn;
    for (final track in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = cameraOn;
    }
    if (!isClosed) emit(state.copyWith(isCameraOn: cameraOn));
  }

  Future<void> switchCamera() async {
    if (!_enableVideo) return;
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first, null, _localStream);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _ensureSignalingConnected(
    String remoteUserId, {
    String? roomId,
  }) async {
    final room = roomId ?? _buildRoomId(_signaling.myUserId, remoteUserId);
    await _signaling.connect(roomId: room);
    _log('signaling connected room=$room my=${_signaling.myUserId} remote=$remoteUserId');
    await _signalSub?.cancel();
    _signalSub = _signaling.messages.listen(_handleSignalingMessage);
  }

  Future<void> _initPeerConnection(String remoteUserId) async {
    _remoteDescriptionReady = false;

    final iceServers = await _signaling.fetchIceServers();
    final normalizedIceServers = iceServers
        .map(_normalizeIceServer)
        .whereType<Map<String, dynamic>>()
        .toList();
    final rtcConfig = {
      'iceServers': normalizedIceServers.isNotEmpty
          ? normalizedIceServers
          : _fallbackRtcConfig()['iceServers'],
      'iceTransportPolicy': _forceRelayCandidatesOnly ? 'relay' : 'all',
      'sdpSemantics': 'unified-plan',
    };
    _log('initPeerConnection relayOnly=$_forceRelayCandidatesOnly useTrickle=$_useTrickleIce iceServers=${rtcConfig['iceServers']}');

    _peerConnection = await createPeerConnection(rtcConfig);
    _log('PeerConnection created, setting callbacks...');
    _iceGatheringCompleter = Completer<void>();

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      }
      _log(
        'onTrack kind=${event.track.kind} id=${event.track.id} enabled=${event.track.enabled} streams=${event.streams.length}',
      );
      if (event.track.kind == 'audio') {
        _remoteAudioTrackCount += 1;
        event.track.enabled = true;
      }
      for (final track in event.streams.expand(
        (stream) => stream.getAudioTracks(),
      )) {
        track.enabled = true;
      }
    };

    _peerConnection!.onAddStream = (stream) {
      _remoteStream = stream;
      _log('onAddStream id=${stream.id} audioTracks=${stream.getAudioTracks().length}');
      for (final track in stream.getAudioTracks()) {
        _remoteAudioTrackCount += 1;
        track.enabled = true;
      }
    };

    _peerConnection!.onIceCandidate = (candidate) async {
      _log('onIceCandidate fired: candidate.candidate="${candidate.candidate}" moreToFollow=${candidate.candidate?.isEmpty ?? true}');
      final raw = candidate.candidate;
      if (raw == null || raw.isEmpty) {
        _log('onIceCandidate: raw is null/empty, ignoring end-of-candidates');
        return;
      }

      _localCandidateCount += 1;
      final relay = _isRelayCandidate(raw);
      final srflx = raw.contains(' typ srflx ');
      final host = raw.contains(' typ host ');
      _log(
        'local candidate gathered count=$_localCandidateCount relay=$relay srflx=$srflx host=$host trickle=$_useTrickleIce',
      );

      if (!_useTrickleIce) {
        return;
      }
      if (_forceRelayCandidatesOnly && !relay) {
        _log('local candidate filtered (non-relay) count=$_localCandidateCount');
        return;
      }
      await _signaling.sendIce(remoteUserId, candidate);
    };

    _peerConnection!.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        final completer = _iceGatheringCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      }
    };

    _peerConnection!.onConnectionState = (state) {
      _log('pcState=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (!isClosed) emit(this.state.copyWith(state: WebRTCCallState.inCall));
        _startDurationTimer();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (!isClosed) {
          emit(this.state.copyWith(state: WebRTCCallState.ended));
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (!isClosed) {
          emit(
            this.state.copyWith(
              state: WebRTCCallState.ended,
              errorMessage: _buildIceFailureMessage(),
            ),
          );
        }
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      _log('iceState=$state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _iceDisconnectTimer?.cancel();
        _iceDisconnectTimer = null;
        _startStatsLogging();
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _iceDisconnectTimer?.cancel();
        _iceDisconnectTimer = Timer(const Duration(seconds: 12), () {
          if (isClosed) return;
          emit(
            this.state.copyWith(
              state: WebRTCCallState.ended,
              errorMessage: '连接中断（ICE断开）',
            ),
          );
        });
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _iceDisconnectTimer?.cancel();
        _iceDisconnectTimer = null;
        if (!isClosed) {
          emit(
            this.state.copyWith(
              state: WebRTCCallState.ended,
              errorMessage: _buildIceFailureMessage(),
            ),
          );
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _iceDisconnectTimer?.cancel();
        _iceDisconnectTimer = null;
        if (!isClosed) {
          emit(this.state.copyWith(state: WebRTCCallState.ended));
        }
      }
    };
  }

  Map<String, dynamic>? _normalizeIceServer(Map<String, dynamic> raw) {
    final urls = raw['urls'];
    if (urls == null) return null;

    final server = <String, dynamic>{'urls': urls};
    final username = raw['username'];
    final credential = raw['credential'];

    if (username is String && username.isNotEmpty) {
      server['username'] = username;
    }
    if (credential is String && credential.isNotEmpty) {
      server['credential'] = credential;
    }

    return server;
  }

  Future<void> _getLocalAudio() async {
    final microphoneStatus = await Permission.microphone.request();
    _log('microphone status: $microphoneStatus');
    if (!microphoneStatus.isGranted) {
      throw Exception('麦克风权限未开启');
    }
    if (_enableVideo) {
      final cameraStatus = await Permission.camera.request();
      _log('camera status: $cameraStatus');
      if (!cameraStatus.isGranted) {
        throw Exception('摄像头权限未开启');
      }
    }
    _log('microphone permission granted, calling getUserMedia...');

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'googEchoCancellation': true,
        'googNoiseSuppression': true,
        'googAutoGainControl': true,
      },
      'video': _enableVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 24},
            }
          : false,
    });
    _log('getUserMedia returned, stream=${_localStream?.id} tracks=${_localStream?.getAudioTracks().length}');
    for (final track in _localStream!.getAudioTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
      _log('local audio track added id=${track.id} enabled=${track.enabled}');
    }
    for (final track in _localStream!.getVideoTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
      _log('local video track added id=${track.id} enabled=${track.enabled}');
    }
    _log('local stream ready id=${_localStream!.id} tracks=${_localStream!.getAudioTracks().length}');
  }

  Future<void> _prepareAudioRouting() async {
    final defaultSpeakerOn = _enableVideo;
    await Helper.setSpeakerphoneOn(defaultSpeakerOn);
    await _selectPreferredAudioOutput(speakerOn: defaultSpeakerOn);
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = true;
    });
    if (!isClosed) {
      emit(
        state.copyWith(
          isMuted: false,
          isSpeakerOn: defaultSpeakerOn,
          isCameraOn: _enableVideo,
        ),
      );
    }
  }

  Map<String, dynamic> _buildSdpConstraints() {
    return {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': _enableVideo,
      },
      'optional': [],
    };
  }

  Future<void> _setRemoteDescription(RTCSessionDescription description) async {
    _log('setRemoteDescription type=${description.type} sdpLen=${description.sdp?.length ?? 0}');
    await _peerConnection?.setRemoteDescription(description);
    _remoteDescriptionReady = true;
    await _flushPendingRemoteCandidates();
  }

  Future<void> _flushPendingRemoteCandidates() async {
    if (!_remoteDescriptionReady || _pendingRemoteCandidates.isEmpty) {
      return;
    }

    final candidates = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    _log('flushPendingRemoteCandidates count=${candidates.length}');
    for (final candidate in candidates) {
      try {
        await _peerConnection?.addCandidate(candidate);
        _remoteCandidateAppliedCount += 1;
      } catch (_) {
        // ignore invalid candidates
      }
    }
  }

  Future<void> _waitForIceGatheringComplete() async {
    final pc = _peerConnection;
    if (pc == null) return;
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }

    final completer = _iceGatheringCompleter;
    if (completer == null) return;

    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      // timeout fallback: continue with available candidates
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _startStatsLogging();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) {
        emit(state.copyWith(durationSeconds: state.durationSeconds + 1));
      }
    });
  }

  Future<void> _handleSignalingMessage(Map<String, dynamic> msg) async {
    final type = msg['type'] as String?;
    _log('signal type=$type from=${msg['from']} to=${msg['to']}');
    switch (type) {
      case 'answer':
        final from = msg['from'] as String?;
        final remoteId = _activeRemoteUserId;
        if (from != null && remoteId != null && from != remoteId) return;

        final receivedAnswer = RTCSessionDescription(msg['sdp'] as String?, 'answer');
        final sdp = _forceRelayCandidatesOnly
            ? _stripNonRelayCandidatesFromSdp(receivedAnswer)
            : receivedAnswer;
        await _setRemoteDescription(sdp);
        if (!isClosed) emit(state.copyWith(state: WebRTCCallState.inCall));
        _startDurationTimer();
        break;

      case 'ice-candidate':
        final from = msg['from'] as String?;
        final remoteId = _activeRemoteUserId;
        if (from != null && remoteId != null && from != remoteId) return;

        final rawCandidate = msg['candidate'] as String?;
        if (rawCandidate == null || rawCandidate.isEmpty) {
          break;
        }
        _remoteCandidateReceivedCount += 1;
        if (_forceRelayCandidatesOnly && !_isRelayCandidate(rawCandidate)) {
          _log('remote candidate filtered (non-relay) rx=$_remoteCandidateReceivedCount');
          break;
        }

        final sdpMid = msg['sdpMid'] as String?;
        final sdpMLineIndex = _parseSdpMLineIndex(msg['sdpMLineIndex']);
        if ((sdpMid == null || sdpMid.isEmpty) && sdpMLineIndex == null) {
          break;
        }

        final candidate = RTCIceCandidate(rawCandidate, sdpMid, sdpMLineIndex);
        if (_peerConnection == null || !_remoteDescriptionReady) {
          _pendingRemoteCandidates.add(candidate);
          _log('remote candidate queued rx=$_remoteCandidateReceivedCount');
        } else {
          try {
            await _peerConnection?.addCandidate(candidate);
            _remoteCandidateAppliedCount += 1;
            _log('remote candidate added add=$_remoteCandidateAppliedCount');
          } catch (_) {
            // ignore invalid candidates
          }
        }
        break;

      case 'offer':
        final from = msg['from'] as String?;
        if (from == null) return;
        final roomId = msg['roomId'] as String?;
        final receivedOffer = RTCSessionDescription(msg['sdp'] as String?, 'offer');
        final sdp = _forceRelayCandidatesOnly
            ? _stripNonRelayCandidatesFromSdp(receivedOffer)
            : receivedOffer;
        await handleOffer(from, sdp, roomId: roomId);
        break;

      case 'hangup':
        await hangUp();
        break;
    }
  }

  String _buildRoomId(String a, String b) {
    final ids = [a, b]..sort();
    return 'call_${ids[0]}_${ids[1]}';
  }

  int? _parseSdpMLineIndex(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool _isRelayCandidate(String candidate) {
    return candidate.contains(' typ relay ');
  }

  Future<void> _selectPreferredAudioOutput({required bool speakerOn}) async {
    try {
      final outputs = await Helper.audiooutputs;
      if (outputs.isEmpty) {
        _log('audio outputs empty');
        return;
      }

      MediaDeviceInfo? preferred;
      final speakerKeywords = ['speaker', 'speakerphone', '扬声器', '免提'];
      final earpieceKeywords = ['earpiece', '听筒'];

      for (final device in outputs) {
        final label = device.label.toLowerCase();
        if (speakerOn &&
            speakerKeywords.any((keyword) => label.contains(keyword))) {
          preferred = device;
          break;
        }
        if (!speakerOn &&
            earpieceKeywords.any((keyword) => label.contains(keyword))) {
          preferred = device;
          break;
        }
      }

      preferred ??= outputs.first;
      await Helper.selectAudioOutput(preferred.deviceId);
      _log(
        'audio output selected speakerOn=$speakerOn id=${preferred.deviceId} label=${preferred.label}',
      );
    } catch (e) {
      _log('select audio output failed speakerOn=$speakerOn error=$e');
    }
  }

  RTCSessionDescription _stripNonRelayCandidatesFromSdp(
    RTCSessionDescription description,
  ) {
    final rawSdp = description.sdp;
    if (rawSdp == null || rawSdp.isEmpty) {
      return description;
    }

    final lines = rawSdp.split('\r\n');
    final filteredLines = <String>[];
    for (final line in lines) {
      if (line.startsWith('a=candidate:') && !_isRelayCandidate(line)) {
        continue;
      }
      filteredLines.add(line);
    }

    return RTCSessionDescription(filteredLines.join('\r\n'), description.type);
  }

  void _resetDiagnostics() {
    _localCandidateCount = 0;
    _remoteCandidateReceivedCount = 0;
    _remoteCandidateAppliedCount = 0;
    _remoteAudioTrackCount = 0;
  }

  String _buildIceFailureMessage() {
    return '连接失败（ICE协商失败）\nlocal=$_localCandidateCount remoteRx=$_remoteCandidateReceivedCount remoteAdd=$_remoteCandidateAppliedCount audio=$_remoteAudioTrackCount';
  }

  void _startStatsLogging() {
    _statsLogTimer?.cancel();
    _statsLogTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final pc = _peerConnection;
      if (pc == null) return;
      try {
        final reports = await _safeGetStats(pc);
        final summary = _summarizeAudioStats(reports);
        if (summary.isNotEmpty) {
          _log('stats $summary');
        }
      } catch (e) {
        _log('stats error=$e');
      }
    });
  }

  Future<List<dynamic>> _safeGetStats(RTCPeerConnection pc) async {
    try {
      final dynamic first = await (pc as dynamic).getStats();
      if (first is List) return first;
      if (first is Iterable) return first.toList();
    } catch (_) {
      final dynamic second = await (pc as dynamic).getStats(null);
      if (second is List) return second;
      if (second is Iterable) return second.toList();
    }
    return const [];
  }

  String _summarizeAudioStats(List<dynamic> reports) {
    int? inBytes;
    int? outBytes;
    int? inPackets;
    int? outPackets;
    String? selectedPair;

    for (final report in reports) {
      if (report is StatsReport) {
        final type = report.type;
        final values = report.values;
        if (type == 'inbound-rtp' && _isAudioStats(values)) {
          inBytes = _toInt(values['bytesReceived']) ?? inBytes;
          inPackets = _toInt(values['packetsReceived']) ?? inPackets;
        } else if (type == 'outbound-rtp' && _isAudioStats(values)) {
          outBytes = _toInt(values['bytesSent']) ?? outBytes;
          outPackets = _toInt(values['packetsSent']) ?? outPackets;
        } else if (type == 'candidate-pair') {
          final selected = values['selected'];
          final nominated = values['nominated'];
          final state = values['state'];
          final isSelected = '$selected' == 'true' || '$nominated' == 'true';
          if (isSelected || '$state' == 'succeeded') {
            selectedPair = 'pair=${report.id} state=$state selected=$selected nominated=$nominated';
          }
        }
      }
    }

    final parts = <String>[];
    if (inBytes != null) parts.add('inBytes=$inBytes');
    if (inPackets != null) parts.add('inPackets=$inPackets');
    if (outBytes != null) parts.add('outBytes=$outBytes');
    if (outPackets != null) parts.add('outPackets=$outPackets');
    if (selectedPair != null) parts.add(selectedPair);
    return parts.join(' ');
  }

  bool _isAudioStats(Map<dynamic, dynamic> values) {
    final kind = values['kind']?.toString().toLowerCase();
    final mediaType = values['mediaType']?.toString().toLowerCase();
    return kind == 'audio' || mediaType == 'audio';
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _log(String message) {
    final log = '[WebRTCCallCubit] $message';
    debugPrint(log);
    developer.log(log, name: 'WebRTCCallCubit');
  }

  Future<void> _cleanup() async {
    await Helper.setSpeakerphoneOn(false);
    _iceDisconnectTimer?.cancel();
    _iceDisconnectTimer = null;
    _statsLogTimer?.cancel();
    _statsLogTimer = null;
    _iceGatheringCompleter = null;
    _pendingRemoteCandidates.clear();
    _remoteDescriptionReady = false;

    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    _remoteStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    _activeRoomId = null;
  }

  @override
  Future<void> close() async {
    _durationTimer?.cancel();
    await _signalSub?.cancel();
    _signalSub = null;
    await _cleanup();
    await _signaling.dispose();
    await super.close();
  }
}
