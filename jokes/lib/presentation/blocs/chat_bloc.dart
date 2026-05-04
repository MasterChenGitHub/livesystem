import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/chat_models.dart';
import '../../services/message_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class ChatState {
  const ChatState({
    required this.messages,
    required this.myId,
    this.isLoading = false,
    this.error,
  });

  final List<ChatMessage> messages;
  final String myId;
  final bool isLoading;
  final String? error;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        myId: myId,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class ChatEvent {
  const ChatEvent();
}

class ChatSendTextRequested extends ChatEvent {
  const ChatSendTextRequested(this.text);
  final String text;
}

class ChatSendImageRequested extends ChatEvent {
  const ChatSendImageRequested(this.imagePath);
  final String imagePath;
}

class ChatLoadMessagesRequested extends ChatEvent {
  const ChatLoadMessagesRequested(this.friendPhone);
  final String friendPhone;
}

class ChatIncomingMessageReceived extends ChatEvent {
  const ChatIncomingMessageReceived(this.message);
  final ChatMessage message;
}

class ChatReadReceiptReceived extends ChatEvent {
  const ChatReadReceiptReceived(this.readerId);
  final String readerId;
}

class ChatDeleteMessagesRequested extends ChatEvent {
  const ChatDeleteMessagesRequested(this.messageIds);
  final Set<String> messageIds;
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required String myId,
    required MessageService messageService,
  })  : _messageService = messageService,
        super(ChatState(messages: const [], myId: myId)) {
    on<ChatSendTextRequested>(_onSendText);
    on<ChatSendImageRequested>(_onSendImage);
    on<ChatLoadMessagesRequested>(_onLoadMessages);
    on<ChatIncomingMessageReceived>(_onIncomingMessage);
    on<ChatReadReceiptReceived>(_onReadReceipt);
    on<ChatDeleteMessagesRequested>(_onDeleteMessages);
  }

  final MessageService _messageService;

  Future<void> _onSendText(ChatSendTextRequested e, Emitter<ChatState> emit) async {
    if (e.text.trim().isEmpty) return;

    final text = e.text.trim();
    // The actual sending is handled by ChatDetailPage via _messageService.sendMessage()
    // Here we just update local state for optimistic UI feedback
    final optimisticMsg = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      senderId: state.myId,
      receiverId: null,
      content: text,
      type: MessageType.text,
      createdAt: DateTime.now(),
    );

    emit(state.copyWith(messages: [...state.messages, optimisticMsg]));
  }

  Future<void> _onSendImage(ChatSendImageRequested e, Emitter<ChatState> emit) async {
    final optimisticMsg = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      senderId: state.myId,
      receiverId: null,
      content: '[图片]',
      type: MessageType.image,
      createdAt: DateTime.now(),
      imageUrl: e.imagePath,
    );

    emit(state.copyWith(messages: [...state.messages, optimisticMsg]));

    try {
      emit(state.copyWith(error: null));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to send image: $e'));
    }
  }

  Future<void> _onLoadMessages(ChatLoadMessagesRequested e, Emitter<ChatState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));

    try {
      final messages = await _messageService.loadMessages(
        friendPhone: e.friendPhone,
      );
      emit(state.copyWith(messages: messages, isLoading: false));
    } catch (e) {
      emit(state.copyWith(
        error: 'Failed to load messages: $e',
        isLoading: false,
      ));
    }
  }

  void _onIncomingMessage(ChatIncomingMessageReceived e, Emitter<ChatState> emit) {
    final exists = state.messages.any((m) => m.id == e.message.id);
    if (exists) return;

    final next = [...state.messages, e.message]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    emit(state.copyWith(messages: next, error: null));
  }

  void _onReadReceipt(ChatReadReceiptReceived e, Emitter<ChatState> emit) {
    final updated = state.messages
        .map(
          (m) => m.senderId == state.myId ? m.copyWith(isRead: true) : m,
        )
        .toList(growable: false);
    emit(state.copyWith(messages: updated));
  }

  void _onDeleteMessages(
    ChatDeleteMessagesRequested e,
    Emitter<ChatState> emit,
  ) {
    if (e.messageIds.isEmpty) return;
    final next = state.messages
        .where((m) => !e.messageIds.contains(m.id))
        .toList(growable: false);
    emit(state.copyWith(messages: next));
  }
}
