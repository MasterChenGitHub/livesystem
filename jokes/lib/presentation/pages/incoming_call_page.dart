import 'package:flutter/material.dart';

import '../../data/models/chat_models.dart';

class IncomingCallPage extends StatelessWidget {
  const IncomingCallPage({
    super.key,
    required this.friend,
    required this.callType,
  });

  final Friend friend;
  final String callType;

  @override
  Widget build(BuildContext context) {
    final isVideo = callType == 'video';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
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
              child: Column(
                children: [
                  const SizedBox(height: 56),
                  CircleAvatar(
                    radius: 52,
                    backgroundImage: friend.avatarUrl.isNotEmpty
                        ? NetworkImage(friend.avatarUrl)
                        : null,
                    child: friend.avatarUrl.isEmpty
                        ? Text(
                            friend.name.isNotEmpty ? friend.name[0] : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    friend.name,
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
                          onTap: () => Navigator.of(context).pop(false),
                        ),
                        _ActionButton(
                          icon: isVideo ? Icons.videocam : Icons.call,
                          label: '接听',
                          color: const Color(0xFF2E7D32),
                          onTap: () => Navigator.of(context).pop(true),
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
