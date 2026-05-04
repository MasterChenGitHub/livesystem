import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/token_storage.dart';
import '../../data/mock/mock_friends.dart';
import '../../services/call_tone_service.dart';
import '../../services/signaling_service.dart';
import 'friend_list_page.dart';
import 'incoming_call_page.dart';
import 'joke_list_page.dart';
import 'mine_page.dart';
import 'video_call_page.dart';
import 'voice_call_page.dart';

class MainTabPage extends StatefulWidget {
  const MainTabPage({super.key});

  @override
  State<MainTabPage> createState() => _MainTabPageState();
}

class _MainTabPageState extends State<MainTabPage> {
  int _currentIndex = 0;
  SignalingService? _incomingSignaling;
  StreamSubscription<Map<String, dynamic>>? _incomingSub;
  bool _incomingInitialized = false;
  bool _showingIncomingDialog = false;
  CallToneKind? _activeIncomingToneKind;

  final _pages = const [JokeListPage(), FriendListPage(), MinePage()];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_incomingInitialized) {
      _incomingInitialized = true;
      unawaited(_initIncomingCallListener());
    }
  }

  Future<void> _initIncomingCallListener() async {
    final storage = context.read<TokenStorage>();
    final token = storage.getToken();
    final myUserId = storage.getPhone();

    if (token == null ||
        token.isEmpty ||
        myUserId == null ||
        myUserId.isEmpty) {
      return;
    }

    final signaling = SignalingService(
      myUserId: myUserId,
      token: token,
    );

    try {
      await signaling.connect(roomId: 'lobby_$myUserId');
      _incomingSignaling = signaling;
      _incomingSub = signaling.messages.listen(_onIncomingSignal);
    } catch (_) {
      await signaling.dispose();
    }
  }

  Future<void> _onIncomingSignal(Map<String, dynamic> message) async {
    if (!mounted) {
      return;
    }

    if (_showingIncomingDialog) {
      final type = message['type'] as String?;
      if (type == 'hangup' && _showingIncomingDialog) {
        final kind = _activeIncomingToneKind ?? CallToneKind.voice;
        CallToneService.instance.stop();
        CallToneService.instance.playHangup(kind);
        _activeIncomingToneKind = null;
        _showingIncomingDialog = false;
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop(false);
        }
      }
      return;
    }

    final type = message['type'] as String?;
    if (type == 'hangup') {
      final kind = _activeIncomingToneKind ?? CallToneKind.voice;
      CallToneService.instance.playHangup(kind);
      return;
    }
    if (type != 'offer') {
      return;
    }

    final from = message['from'] as String?;
    final sdp = message['sdp'] as String?;
    final roomId = message['roomId'] as String?;
    final callType = (message['callType'] as String? ?? 'voice').toLowerCase();
    if (from == null || from.isEmpty || sdp == null || sdp.isEmpty) {
      return;
    }

    final caller = resolveIncomingFriend(from);
    final toneKind =
      callType == 'video' ? CallToneKind.video : CallToneKind.voice;
    _activeIncomingToneKind = toneKind;

    _showingIncomingDialog = true;
    CallToneService.instance.startIncoming(toneKind);
    final accepted = await Navigator.of(context, rootNavigator: true).push<bool>(
      PageRouteBuilder<bool>(
        opaque: true,
        pageBuilder: (ctx, animation, secondaryAnimation) => IncomingCallPage(
          friend: caller,
          callType: callType,
        ),
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    CallToneService.instance.stop();
    _showingIncomingDialog = false;
    _activeIncomingToneKind = null;

    if (!mounted) {
      return;
    }

    if (accepted == true) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => callType == 'video'
              ? VideoCallPage(
                  friend: caller,
                  incomingOfferSdp: sdp,
                  incomingRoomId: roomId,
                )
              : VoiceCallPage(
                  friend: caller,
                  incomingOfferSdp: sdp,
                  incomingRoomId: roomId,
                ),
        ),
      );
    } else {
      CallToneService.instance.playHangup(toneKind);
      await _incomingSignaling?.sendHangup(from);
    }
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _incomingSignaling?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: '聊天',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
