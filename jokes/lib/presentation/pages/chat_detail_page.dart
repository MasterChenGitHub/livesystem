import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../data/datasources/token_storage.dart';
import '../../data/models/chat_models.dart';
import '../../services/chat_realtime_service.dart';
import '../../services/friend_directory_service.dart';
import '../../services/image_preprocess_service.dart';
import '../../services/message_service.dart';
import '../../services/video_preprocess_service.dart';
import '../blocs/chat_bloc.dart';
import 'video_call_page.dart';
import 'voice_call_page.dart';

class ChatDetailPage extends StatefulWidget {
  const ChatDetailPage({super.key, required this.friend});

  final Friend friend;

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  static const String _deleteBoxName = 'message_delete_box';
  final _inputController = TextEditingController();
  final _inputBarKey = GlobalKey<_InputBarState>();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final _imagePreprocessService = ImagePreprocessService();
  final _videoPreprocessService = VideoPreprocessService();
  late ChatBloc _chatBloc;
  late MessageService _messageService;
  ChatRealtimeService? _chatRealtimeService;
  StreamSubscription<ChatMessage>? _chatRealtimeSub;
  StreamSubscription<TypingEvent>? _typingSub;
  StreamSubscription<PresenceEvent>? _presenceSub;
  StreamSubscription<ReadReceiptEvent>? _readSub;
  Timer? _typingDebounce;
  bool _friendTyping = false;
  bool _friendOnline = false;
  bool _initialized = false;
  bool _deleteStoreReady = false;
  String _myId = '';
  String _myAvatar = '';
  final Set<String> _selectedMessageIds = <String>{};
  final Set<String> _locallyHiddenMessageIds = <String>{};
  Box<String>? _deleteBox;

  bool get _isSelectionMode => _selectedMessageIds.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final tokenStorage = context.read<TokenStorage>();
      final myId = tokenStorage.getPhone() ?? 'me';
      final myAvatar = tokenStorage.getAvatar() ?? '';
      _myId = myId;
      _myAvatar = myAvatar;
      final dio = context.read<Dio>();
      final token = tokenStorage.getToken();
      
      _messageService = MessageService(
        dio: dio,
        tokenStorage: tokenStorage,
      );
      
      _chatBloc = ChatBloc(
        myId: myId,
        messageService: _messageService,
      );
      
      _initialized = true;
      unawaited(_initDeleteStoreAndSync());
      
      // Load existing messages when entering chat
      _loadMessages();
      _markCurrentConversationRead();

      if (token != null && token.isNotEmpty) {
        _chatRealtimeService = ChatRealtimeService(
          apiBaseUrl: dio.options.baseUrl,
          token: token,
        );
        _connectRealtime();
      }
    }
  }

  Future<void> _connectRealtime() async {
    final service = _chatRealtimeService;
    if (service == null) return;

    try {
      await service.connect();
      unawaited(_syncPendingDeletes());
      _chatRealtimeSub = service.messages.listen((message) {
        final fromCurrentFriend = message.senderId == widget.friend.id;
        if (!fromCurrentFriend) return;
        if (!mounted) return;

        _chatBloc.add(ChatIncomingMessageReceived(message));
        context.read<FriendDirectoryService>().applyIncomingMessage(
          myId: _chatBloc.state.myId,
          message: message,
        );
        _markCurrentConversationRead();
        context.read<FriendDirectoryService>().markConversationReadLocal(widget.friend.id);
        _scrollToBottom();
      });
      _typingSub = service.typing.listen((event) {
        if (event.fromUserId != widget.friend.id) return;
        if (!mounted) return;
        setState(() {
          _friendTyping = event.isTyping;
        });
      });
      _presenceSub = service.presence.listen((event) {
        if (event.userId != widget.friend.id) return;
        if (!mounted) return;
        setState(() {
          _friendOnline = event.online;
        });
      });
      _readSub = service.readReceipts.listen((event) {
        if (event.readerId != widget.friend.id) return;
        _chatBloc.add(ChatReadReceiptReceived(event.readerId));
      });
    } catch (_) {
      // Realtime connection failed; user can still read messages via API.
    }
  }

  Future<void> _loadMessages() async {
    _chatBloc.add(ChatLoadMessagesRequested(widget.friend.id));
  }

  String get _pendingDeleteKey => 'pending_delete:$_myId:${widget.friend.id}';
  String get _hiddenDeleteKey => 'hidden_delete:$_myId:${widget.friend.id}';

  Future<void> _initDeleteStoreAndSync() async {
    _deleteBox ??= await Hive.openBox<String>(_deleteBoxName);
    _locallyHiddenMessageIds
      ..clear()
      ..addAll(_readStoredIds(_hiddenDeleteKey));
    if (!mounted) return;
    setState(() {
      _deleteStoreReady = true;
    });
    await _syncPendingDeletes();
  }

  Set<String> _readStoredIds(String key) {
    final raw = _deleteBox?.get(key);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toSet();
      }
    } catch (_) {
      // ignore malformed payload
    }
    return <String>{};
  }

  Future<void> _writeStoredIds(String key, Set<String> ids) async {
    await _deleteBox?.put(key, jsonEncode(ids.toList(growable: false)));
  }

  Future<void> _hideMessagesLocally(Set<String> messageIds) async {
    if (messageIds.isEmpty) return;
    _locallyHiddenMessageIds.addAll(messageIds);
    await _writeStoredIds(_hiddenDeleteKey, _locallyHiddenMessageIds);
  }

  Future<void> _enqueuePendingDeletes(Set<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final pending = _readStoredIds(_pendingDeleteKey)..addAll(messageIds);
    await _writeStoredIds(_pendingDeleteKey, pending);
  }

  Future<void> _syncPendingDeletes() async {
    if (!_deleteStoreReady) return;
    final pending = _readStoredIds(_pendingDeleteKey);
    if (pending.isEmpty) return;

    try {
      final deleted = await _messageService.deleteConversationMessages(
        friendPhone: widget.friend.id,
        messageIds: pending,
      );
      if (deleted <= 0) return;

      await _writeStoredIds(_pendingDeleteKey, <String>{});
      _locallyHiddenMessageIds.removeAll(pending);
      await _writeStoredIds(_hiddenDeleteKey, _locallyHiddenMessageIds);
      if (mounted) {
        _loadMessages();
      }
    } catch (_) {
      // keep pending queue for later retry
    }
  }

  Future<void> _markCurrentConversationRead() async {
    try {
      await _messageService.markConversationRead(friendPhone: widget.friend.id);
      if (mounted) {
        context.read<FriendDirectoryService>().markConversationReadLocal(widget.friend.id);
      }
    } catch (_) {}
  }

  void _onInputChanged(String value) {
    final service = _chatRealtimeService;
    if (service == null) return;

    if (value.trim().isEmpty) {
      service.sendTyping(toUserId: widget.friend.id, isTyping: false);
      _typingDebounce?.cancel();
      return;
    }

    service.sendTyping(toUserId: widget.friend.id, isTyping: true);
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 1200), () {
      service.sendTyping(toUserId: widget.friend.id, isTyping: false);
    });
  }

  @override
  void dispose() {
    _chatRealtimeSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();
    _readSub?.cancel();
    _typingDebounce?.cancel();
    if (_chatRealtimeService != null) {
      unawaited(_chatRealtimeService!.dispose());
    }
    _inputController.dispose();
    _scrollController.dispose();
    _chatBloc.close();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    final result = await _picker.pickImage(source: ImageSource.gallery);
    if (result == null) return;

    try {
      // Step 1: Compress image
      final prepared = await _imagePreprocessService.prepare(result);

      // Step 2: Direct upload to OSS (bypass server)
      final upload = await _messageService.uploadFileDirectToOss(
        filePath: prepared.mainPath,
        fileType: 'image',
        thumbPath: prepared.thumbPath,
      );

      // Step 3: Send message with CDN URL via WebSocket
      final sent = await _messageService.sendMessage(
        receiverPhone: widget.friend.id,
        content: '[图片]',
        type: 'image',
        imageUrl: upload['url']?.toString(),
        thumbUrl: upload['thumbUrl']?.toString(),
        imageWidth: prepared.width,
        imageHeight: prepared.height,
        imageSize: prepared.size,
      );

      if (sent != null && mounted) {
        _chatBloc.add(ChatIncomingMessageReceived(sent));
        context.read<FriendDirectoryService>().applyIncomingMessage(
          myId: _chatBloc.state.myId,
          message: sent,
        );
      }

      await _imagePreprocessService.cleanup(prepared);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图片发送失败: $e')),
      );
    }
  }

  Future<void> _pickVideo() async {
    final result = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (result == null) return;

    // Show progress indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('视频处理中...'), duration: Duration(days: 1)),
      );
    }

    try {
      // Step 1: Extract thumbnail from first frame + optional compression
      final prepared = await _videoPreprocessService.prepare(result.path);

      // Step 2: Direct upload video to OSS
      final upload = await _messageService.uploadFileDirectToOss(
        filePath: prepared.videoPath,
        fileType: 'video',
        thumbPath: prepared.thumbPath,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Step 3: Send message with video CDN URL via WebSocket
      final sent = await _messageService.sendMessage(
        receiverPhone: widget.friend.id,
        content: '[视频]',
        type: 'video',
        videoUrl: upload['url']?.toString(),
        videoThumbUrl: upload['thumbUrl']?.toString(),
        videoDuration: prepared.duration,
        videoWidth: prepared.width,
        videoHeight: prepared.height,
      );

      if (sent != null && mounted) {
        _chatBloc.add(ChatIncomingMessageReceived(sent));
        context.read<FriendDirectoryService>().applyIncomingMessage(
          myId: _chatBloc.state.myId,
          message: sent,
        );
      }

      await _videoPreprocessService.cleanup(prepared);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('视频发送失败: $e')),
      );
    }
  }

  Future<void> _sendVoice(String filePath, int durationSeconds) async {
    try {
      final upload = await _messageService.uploadFileDirectToOss(
        filePath: filePath,
        fileType: 'voice',
      );

      final sent = await _messageService.sendMessage(
        receiverPhone: widget.friend.id,
        content: '[语音] ${durationSeconds}s',
        type: 'voice',
        voiceUrl: upload['url']?.toString(),
        voiceDuration: durationSeconds,
      );

      if (sent != null && mounted) {
        _chatBloc.add(ChatIncomingMessageReceived(sent));
        context.read<FriendDirectoryService>().applyIncomingMessage(
          myId: _chatBloc.state.myId,
          message: sent,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('语音发送失败: $e')),
        );
      }
    } finally {
      try {
        final f = File(filePath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
    _scrollToBottom();
  }

  Future<void> _sendText() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _chatRealtimeService?.sendTyping(toUserId: widget.friend.id, isTyping: false);
    _typingDebounce?.cancel();
    _inputController.clear();
    
    try {
      // Send message to server
      final sent = await _messageService.sendMessage(
        receiverPhone: widget.friend.id,
        content: text,
        type: 'text',
      );

      if (sent != null && mounted) {
        _chatBloc.add(ChatIncomingMessageReceived(sent));
        context.read<FriendDirectoryService>().applyIncomingMessage(
          myId: _chatBloc.state.myId,
          message: sent,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    }
    _scrollToBottom();
  }

  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _clearSelection() {
    if (_selectedMessageIds.isEmpty) return;
    setState(() {
      _selectedMessageIds.clear();
    });
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;

    final count = _selectedMessageIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除消息'),
        content: Text('确认删除这 $count 条消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final toDelete = Set<String>.from(_selectedMessageIds);
    await _hideMessagesLocally(toDelete);
    _chatBloc.add(ChatDeleteMessagesRequested(toDelete));
    _clearSelection();

    try {
      await _messageService.deleteConversationMessages(
        friendPhone: widget.friend.id,
        messageIds: toDelete,
      );
      _locallyHiddenMessageIds.removeAll(toDelete);
      await _writeStoredIds(_hiddenDeleteKey, _locallyHiddenMessageIds);
    } catch (e) {
      await _enqueuePendingDeletes(toDelete);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已离线删除，联网后会自动同步')),
      );
    }
  }

  Future<void> _handleMessageTap(ChatMessage message) async {
    if (_isSelectionMode) {
      _toggleMessageSelection(message.id);
      return;
    }

    final isVoiceCallRecord =
        message.type == MessageType.voice &&
        message.voiceUrl == null &&
        message.content.contains('语音通话');
    if (isVoiceCallRecord) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VoiceCallPage(friend: widget.friend),
        ),
      );
      return;
    }

    final isVideoCallRecord =
        message.type == MessageType.video &&
        message.videoUrl == null &&
        message.content.contains('视频通话');
    if (isVideoCallRecord) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoCallPage(friend: widget.friend),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _chatBloc,
      child: BlocBuilder<ChatBloc, ChatState>(
        builder: (context, chatState) {
          final messages = chatState.messages
              .where((m) => !_locallyHiddenMessageIds.contains(m.id))
              .toList(growable: false);
          final myId = chatState.myId;
          final isLoading = chatState.isLoading;
          final error = chatState.error;

          if (messages.isNotEmpty) _scrollToBottom();

          return Scaffold(
            backgroundColor: const Color(0xFFEDEDED),
            appBar: AppBar(
              backgroundColor: const Color(0xFFF7F7F7),
              surfaceTintColor: Colors.transparent,
              elevation: 0.6,
              foregroundColor: Colors.black87,
              leading: _isSelectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _clearSelection,
                    )
                  : null,
              title: _isSelectionMode
                  ? Text('已选择 ${_selectedMessageIds.length} 条')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.friend.name),
                        // Text(
                        //   _friendTyping
                        //       ? '正在输入…'
                        //       : (_friendOnline ? '在线' : '离线'),
                        //   style: const TextStyle(
                        //     fontSize: 12,
                        //     fontWeight: FontWeight.normal,
                        //     color: Colors.black54,
                        //   ),
                        // ),
                      ],
                    ),
              actions: [
                if (_isSelectionMode)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '删除消息',
                    onPressed: _deleteSelectedMessages,
                  ),
              ],
            ),
            body: Column(
              children: [
                if (error != null)
                  Container(
                    color: Colors.red.shade100,
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: isLoading && messages.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _inputBarKey.currentState?.hidePanel(),
                          child: messages.isEmpty
                          ? const Center(
                              child: Text(
                                '发个消息打个招呼吧 👋',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 8),
                              itemCount: messages.length,
                              itemBuilder: (_, index) {
                                final msg = messages[index];
                                final isMe = msg.senderId == myId;
                                final isSelected = _selectedMessageIds.contains(
                                  msg.id,
                                );
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPress: () => _toggleMessageSelection(msg.id),
                                  onTap: () => _handleMessageTap(msg),
                                  child: _MessageBubble(
                                    message: msg,
                                    isMe: isMe,
                                    senderName: isMe ? '我' : widget.friend.name,
                                    senderAvatar: isMe ? _myAvatar : widget.friend.avatarUrl,
                                    senderInitial: isMe
                                        ? '我'
                                        : widget.friend.name.isNotEmpty
                                            ? widget.friend.name[0]
                                            : '?',
                                    showReadStatus: isMe,
                                    isSelected: isSelected,
                                  ),
                                );
                              },
                            ),
                        ),
                ),
                if (!_isSelectionMode)
                  _InputBar(
                    key: _inputBarKey,
                    controller: _inputController,
                    onSend: _sendText,
                    onPickImage: _pickImage,
                    onPickVideo: _pickVideo,
                    onStartVoiceCall: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => VoiceCallPage(friend: widget.friend),
                        ),
                      );
                    },
                    onStartVideoCall: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => VideoCallPage(friend: widget.friend),
                        ),
                      );
                    },
                    onSendVoice: _sendVoice,
                    onChanged: _onInputChanged,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message Bubble
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.senderName,
    required this.senderAvatar,
    required this.senderInitial,
    this.showReadStatus = false,
    this.isSelected = false,
  });

  final ChatMessage message;
  final bool isMe;
  final String senderName;
  final String senderAvatar;
  final String senderInitial;
  final bool showReadStatus;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: 18,
      backgroundImage:
          senderAvatar.isNotEmpty ? NetworkImage(senderAvatar) : null,
      child: senderAvatar.isEmpty
          ? Text(senderInitial, style: const TextStyle(fontSize: 12))
          : null,
    );

    final bubble = _buildContent(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: isMe
                ? [bubble, const SizedBox(width: 8), avatar]
                : [avatar, const SizedBox(width: 8), bubble],
          ),
          if (isSelected)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: const [
                  Icon(Icons.check_circle, size: 16, color: Colors.blue),
                ],
              ),
            ),
          if (showReadStatus)
            Padding(
              padding: const EdgeInsets.only(right: 44, top: 2),
              child: Text(
                message.isRead ? '已读' : '未读',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (message.isImage && message.imageUrl != null) {
      final preview = (message.thumbUrl ?? message.imageUrl)!;
      return GestureDetector(
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: InteractiveViewer(
                child: Image.network(
                  message.imageUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, size: 80),
                ),
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            preview,
            width: 180,
            height: 180,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 60),
          ),
        ),
      );
    }

    if (message.isVideo && message.videoUrl != null) {
      // Show thumbnail with play icon overlay
      final thumb = message.videoThumbUrl;
      final duration = message.videoDuration;
      final durationStr = duration != null
          ? '${(duration ~/ 60000).toString().padLeft(2, '0')}:${((duration % 60000) ~/ 1000).toString().padLeft(2, '0')}'
          : '';
      return GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _VideoPlayerDialog(url: message.videoUrl!),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (thumb != null)
                Image.network(
                  thumb,
                  width: 180,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 180,
                    height: 180,
                    color: Colors.black54,
                    child: const Icon(Icons.videocam, color: Colors.white, size: 60),
                  ),
                )
              else
                Container(
                  width: 180,
                  height: 180,
                  color: Colors.black54,
                  child: const Icon(Icons.videocam, color: Colors.white, size: 60),
                ),
              const CircleAvatar(
                radius: 24,
                backgroundColor: Colors.black45,
                child: Icon(Icons.play_arrow, color: Colors.white, size: 32),
              ),
              if (durationStr.isNotEmpty)
                Positioned(
                  bottom: 6,
                  right: 8,
                  child: Text(
                    durationStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (message.isVoice && message.voiceUrl != null) {
      final sec = message.voiceDuration ?? 0;
      return GestureDetector(
        onTap: () async {
          try {
            final player = AudioPlayer();
            await player.play(UrlSource(message.voiceUrl!));
          } catch (_) {}
        },
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.55,
            minWidth: 120,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF95EC69) : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(6),
              topRight: const Radius.circular(6),
              bottomLeft: Radius.circular(isMe ? 6 : 2),
              bottomRight: Radius.circular(isMe ? 2 : 6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isMe ? Icons.graphic_eq : Icons.multitrack_audio,
                size: 20,
                color: Colors.black87,
              ),
              const SizedBox(width: 8),
              Text(
                '${sec}s',
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.65,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF95EC69) : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
          bottomLeft: Radius.circular(isMe ? 6 : 2),
          bottomRight: Radius.circular(isMe ? 2 : 6),
        ),
      ),
      child: Text(
        message.content,
        style: const TextStyle(color: Colors.black87),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input Bar
// ---------------------------------------------------------------------------

class _InputBar extends StatefulWidget {
  _InputBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onStartVoiceCall,
    required this.onStartVideoCall,
    required this.onSendVoice,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final VoidCallback onStartVoiceCall;
  final VoidCallback onStartVideoCall;
  final Future<void> Function(String filePath, int durationSeconds) onSendVoice;
  final ValueChanged<String> onChanged;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recordTimer;
  bool _voiceMode = false;
  bool _isRecording = false;
  bool _showPanel = false;
  int _recordSeconds = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }


  void hidePanel() {
    if (_showPanel) setState(() => _showPanel = false);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onInputChanged);
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先开启麦克风权限')),
      );
      return;
    }

    final tmpDir = await getTemporaryDirectory();
    final path = '${tmpDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    _recordSeconds = 0;
    _isRecording = true;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _recordSeconds += 1;
      });
      if (_recordSeconds >= 60) {
        unawaited(_stopRecordingAndSend(force60s: true));
      }
    });
    if (mounted) setState(() {});
  }

  Future<void> _stopRecordingAndSend({bool force60s = false}) async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;

    final path = await _recorder.stop();
    final duration = force60s ? 60 : _recordSeconds;
    _isRecording = false;
    _recordSeconds = 0;
    if (mounted) setState(() {});

    if (path == null || duration <= 0) return;
    await widget.onSendVoice(path, duration);
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          border: const Border(
            top: BorderSide(color: Colors.black12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isRecording)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _recordSeconds >= 50
                      ? '录音中，还可录 ${60 - _recordSeconds}s'
                      : '录音中 ${_recordSeconds}s',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: Icon(_voiceMode ? Icons.keyboard : Icons.mic_none,
                      color: Colors.black54),
                  tooltip: _voiceMode ? '键盘输入' : '语音输入',
                  onPressed: () {
                    setState(() {
                      _voiceMode = !_voiceMode;
                    });
                  },
                  color: Colors.black54,
                ),
                Expanded(
                  child: _voiceMode
                      ? GestureDetector(
                          onLongPressStart: (_) => _startRecording(),
                          onLongPressEnd: (_) => _stopRecordingAndSend(),
                          onLongPressCancel: _stopRecordingAndSend,
                          child: Container(
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _isRecording ? const Color(0xFFFFEAEA) : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _isRecording ? Colors.redAccent : Colors.black12,
                              ),
                            ),
                            child: Text(
                              _isRecording ? '松开发送' : '按住 说话',
                              style: TextStyle(
                                color: _isRecording ? Colors.redAccent : Colors.black87,
                              ),
                            ),
                          ),
                        )
                      : TextField(
                          controller: widget.controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          decoration: const InputDecoration(
                            hintText: '发送消息…',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(6)),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(6)),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(6)),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            isDense: true,
                          ),
                          onSubmitted: (_) => widget.onSend(),
                          onChanged: widget.onChanged,
                        ),
                ),
                const SizedBox(width: 4),
                if (!_voiceMode && hasText)
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: const Color(0xFF07C160),
                    onPressed: widget.onSend,
                  )
                else
                  IconButton(
                    icon: Icon(_showPanel ? Icons.add_circle : Icons.add_circle_outline,
                        color: _showPanel ? const Color(0xFF07C160) : Colors.black54),
                    onPressed: () {
                      setState(() => _showPanel = !_showPanel);
                      if (_showPanel) FocusScope.of(context).unfocus();
                    },
                  ),
              ],
            ),
            if (_showPanel) _buildInlinePanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildInlinePanel() {
    final items = [
      _PlusPanelItem(icon: Icons.photo, label: '相册', onTap: () { setState(() => _showPanel = false); widget.onPickImage(); }),
      _PlusPanelItem(icon: Icons.videocam, label: '视频', onTap: () { setState(() => _showPanel = false); widget.onPickVideo(); }),
      _PlusPanelItem(icon: Icons.call, label: '语音通话', onTap: () { setState(() => _showPanel = false); widget.onStartVoiceCall(); }),
      _PlusPanelItem(icon: Icons.video_call, label: '视频通话', onTap: () { setState(() => _showPanel = false); widget.onStartVideoCall(); }),
    ];
    return Container(
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.75,
        children: items.map((e) => GestureDetector(
          onTap: e.onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(e.icon, size: 28, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              Text(e.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  const _VideoPlayerDialog({required this.url});

  final String url;

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      await controller.setLooping(false);
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '视频播放失败: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('视频播放'),
      content: SizedBox(
        width: 320,
        child: _loading
            ? const AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
            ? Text(_error!)
            : _controller == null
            ? const Text('视频初始化失败')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio > 0
                        ? _controller!.value.aspectRatio
                        : 16 / 9,
                    child: VideoPlayer(_controller!),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          final c = _controller!;
                          if (c.value.isPlaying) {
                            c.pause();
                          } else {
                            c.play();
                          }
                          setState(() {});
                        },
                        icon: Icon(
                          _controller!.value.isPlaying
                              ? Icons.pause_circle
                              : Icons.play_circle,
                        ),
                      ),
                      Expanded(
                        child: VideoProgressIndicator(
                          _controller!,
                          allowScrubbing: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _PlusPanelItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PlusPanelItem({required this.icon, required this.label, required this.onTap});
}
