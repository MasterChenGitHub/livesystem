enum MessageType { text, image, video, voice }

class Friend {
  const Friend({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    this.lastMessage = '',
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
    this.isTyping = false,
  });

  final String id;
  final String name;
  final String avatarUrl;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  final bool isTyping;

  Friend copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
    bool? isTyping,
  }) {
    return Friend(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      isTyping: isTyping ?? this.isTyping,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    this.receiverId,
    required this.content,
    required this.type,
    required this.createdAt,
    this.imageUrl,
    this.thumbUrl,
    this.imageWidth,
    this.imageHeight,
    this.imageSize,
    this.videoUrl,
    this.videoThumbUrl,
    this.videoDuration,
    this.videoWidth,
    this.videoHeight,
    this.voiceUrl,
    this.voiceDuration,
    this.isRead = false,
  });

  final String id;
  final String senderId;
  final String? receiverId;
  final String content;
  final MessageType type;
  final DateTime createdAt;
  final String? imageUrl;
  final String? thumbUrl;
  final int? imageWidth;
  final int? imageHeight;
  final int? imageSize;
  final String? videoUrl;
  final String? videoThumbUrl;
  final int? videoDuration; // milliseconds
  final int? videoWidth;
  final int? videoHeight;
  final String? voiceUrl;
  final int? voiceDuration; // seconds
  final bool isRead;

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? content,
    MessageType? type,
    DateTime? createdAt,
    String? imageUrl,
    String? thumbUrl,
    int? imageWidth,
    int? imageHeight,
    int? imageSize,
    String? videoUrl,
    String? videoThumbUrl,
    int? videoDuration,
    int? videoWidth,
    int? videoHeight,
    String? voiceUrl,
    int? voiceDuration,
    bool? isRead,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbUrl: thumbUrl ?? this.thumbUrl,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      imageSize: imageSize ?? this.imageSize,
      videoUrl: videoUrl ?? this.videoUrl,
      videoThumbUrl: videoThumbUrl ?? this.videoThumbUrl,
      videoDuration: videoDuration ?? this.videoDuration,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      voiceUrl: voiceUrl ?? this.voiceUrl,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      isRead: isRead ?? this.isRead,
    );
  }

  bool get isImage => type == MessageType.image;
  bool get isVideo => type == MessageType.video;
  bool get isVoice => type == MessageType.voice;
}
