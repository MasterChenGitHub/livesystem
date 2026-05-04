import 'dart:io';
import 'package:dio/dio.dart';

import '../data/datasources/token_storage.dart';
import '../data/models/chat_models.dart';

class UploadTokenResponse {
  final String uploadUrl;
  final String token;
  final String key;
  final String accessKeyId;
  final String policy;

  UploadTokenResponse({
    required this.uploadUrl,
    required this.token,
    required this.key,
    required this.accessKeyId,
    required this.policy,
  });

  factory UploadTokenResponse.fromJson(Map<String, dynamic> json) {
    return UploadTokenResponse(
      uploadUrl: json['uploadUrl'] as String,
      token: json['token'] as String,
      key: json['key'] as String,
      accessKeyId: json['accessKeyId'] as String,
      policy: json['policy'] as String,
    );
  }
}

class MessageService {
  MessageService({
    required Dio dio,
    required TokenStorage tokenStorage,
  }) : _dio = dio,
       _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  /// Step 1: Get upload token from server
  /// Step 1: Get upload token from server (one token per upload session)
  /// Step 2: Direct upload main file + optional thumbnail to OSS
  /// Step 3: Return CDN URLs
  Future<Map<String, dynamic>> uploadFileDirectToOss({
    required String filePath,
    required String fileType, // "image" / "video" / "voice"
    String? thumbPath, // thumbnail for both image and video
  }) async {
    final token = _tokenStorage.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('No authentication token');
    }

    try {
      // Step 1: Get upload token (key includes correct extension based on fileType)
      final tokenResponse = await _dio.post<Map<String, dynamic>>(
        '/upload/token',
        queryParameters: {'fileType': fileType},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (tokenResponse.statusCode != 200 || tokenResponse.data == null) {
        throw Exception('Failed to get upload token');
      }

      final uploadToken = UploadTokenResponse.fromJson(tokenResponse.data!);

      // Step 2a: Upload main file to OSS
      final fileUrl = await _uploadToOss(
        uploadToken: uploadToken,
        filePath: filePath,
      );

      // Step 2b: Upload thumbnail if provided (image thumb or video first-frame)
      String? thumbUrl;
      if (thumbPath != null) {
        thumbUrl = await _uploadToOss(
          uploadToken: uploadToken,
          filePath: thumbPath,
          isThumb: true,
        );
      }

      return {
        'url': fileUrl,
        'thumbUrl': thumbUrl,
        'key': uploadToken.key,
      };
    } catch (e) {
      throw Exception('Direct OSS upload failed: $e');
    }
  }

  /// Upload file directly to OSS via PostObject (multipart/form-data)
  /// Required form fields: key, OSSAccessKeyId, policy, Signature, Content-Type, file
  Future<String> _uploadToOss({
    required UploadTokenResponse uploadToken,
    required String filePath,
    bool isThumb = false,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    // Construct key for this file
    String key = uploadToken.key;
    if (isThumb) {
      // Thumbnail is always JPEG regardless of main file type (e.g. video thumb → .jpg not .mp4)
      // chat/2026/04/28/uuid.mp4 → chat/2026/04/28/uuid_thumb.jpg
      key = key.replaceAllMapped(
        RegExp(r'^(.*?)(\.\w+)$'),
        (m) => '${m[1]}_thumb.jpg',
      );
    }

    final contentType = _getContentType(filePath);

    // OSS PostObject requires these form fields in exact order
    final formData = FormData.fromMap({
      'key': key,
      'OSSAccessKeyId': uploadToken.accessKeyId,
      'policy': uploadToken.policy,
      'Signature': uploadToken.token,       // HMAC-SHA1 signature of the policy
      'Content-Type': contentType,
      'success_action_status': '200',        // Return 200 instead of default 204
      'file': await MultipartFile.fromFile(
        filePath,
        contentType: DioMediaType.parse(contentType),
      ),
    });

    // POST to OSS bucket endpoint
    final response = await Dio().post<dynamic>(
      uploadToken.uploadUrl,
      data: formData,
      options: Options(
        validateStatus: (status) => status != null,
      ),
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      // Return the public CDN URL of the uploaded file
      return '${uploadToken.uploadUrl}/$key';
    }
    throw Exception(
      'OSS upload failed with status ${response.statusCode}: '
      '${response.data}',
    );
  }

  String _getContentType(String filePath) {
    if (filePath.endsWith('.mp4')) return 'video/mp4';
    if (filePath.endsWith('.m4a')) return 'audio/mp4';
    if (filePath.endsWith('.aac')) return 'audio/aac';
    if (filePath.endsWith('.amr')) return 'audio/amr';
    if (filePath.endsWith('.wav')) return 'audio/wav';
    if (filePath.endsWith('.jpg') || filePath.endsWith('.jpeg')) return 'image/jpeg';
    if (filePath.endsWith('.png')) return 'image/png';
    if (filePath.endsWith('.gif')) return 'image/gif';
    return 'application/octet-stream';
  }

  /// Send a text/image/video/voice message to a friend
  Future<ChatMessage?> sendMessage({
    required String receiverPhone,
    required String content,
    String type = 'text',
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
  }) async {
    final token = _tokenStorage.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('No authentication token');
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/messages/send',
        data: {
          'receiverPhone': receiverPhone,
          'content': content,
          'type': type,
          'imageUrl': imageUrl,
          'thumbUrl': thumbUrl,
          'imageWidth': imageWidth,
          'imageHeight': imageHeight,
          'imageSize': imageSize,
          'videoUrl': videoUrl,
          'videoThumbUrl': videoThumbUrl,
          'videoDuration': videoDuration,
          'videoWidth': videoWidth,
          'videoHeight': videoHeight,
          'voiceUrl': voiceUrl,
          'voiceDuration': voiceDuration,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return _parseMessage(response.data!);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  /// Get all messages in a conversation with a friend
  /// Returns messages sorted by createdAt (oldest first)
  Future<List<ChatMessage>> loadMessages({
    required String friendPhone,
    int limit = 100,
  }) async {
    final token = _tokenStorage.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('No authentication token');
    }

    try {
      final response = await _dio.get<List<dynamic>>(
        '/messages/list',
        queryParameters: {
          'friendPhone': friendPhone,
          'limit': limit,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data!.map((item) {
          return _parseMessage(item as Map<String, dynamic>);
        }).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Failed to load messages: $e');
    }
  }

  Future<void> markConversationRead({required String friendPhone}) async {
    final token = _tokenStorage.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('No authentication token');
    }

    await _dio.post<dynamic>(
      '/messages/read',
      data: {'friendPhone': friendPhone},
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
        },
      ),
    );
  }

  Future<int> deleteConversationMessages({
    required String friendPhone,
    required Set<String> messageIds,
  }) async {
    final token = _tokenStorage.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('No authentication token');
    }

    final ids = messageIds
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .toList(growable: false);

    if (ids.isEmpty) return 0;

    final response = await _dio.post<Map<String, dynamic>>(
      '/messages/delete',
      data: {
        'friendPhone': friendPhone,
        'messageIds': ids,
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
        },
      ),
    );

    if (response.statusCode == 200) {
      return int.tryParse((response.data?['deleted'] ?? 0).toString()) ?? 0;
    }
    throw Exception('Failed to delete messages');
  }

  /// Parse a message JSON object from the API response
  ChatMessage _parseMessage(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      senderId: json['senderPhone'] as String,
      receiverId: json['receiverPhone']?.toString(),
      content: json['content'] as String,
      type: _parseMessageType(json['type'] as String? ?? 'text'),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      imageUrl: json['imageUrl'] as String?,
      thumbUrl: json['thumbUrl']?.toString(),
      imageWidth: int.tryParse((json['imageWidth'] ?? '').toString()),
      imageHeight: int.tryParse((json['imageHeight'] ?? '').toString()),
      imageSize: int.tryParse((json['imageSize'] ?? '').toString()),
      videoUrl: json['videoUrl'] as String?,
      videoThumbUrl: json['videoThumbUrl']?.toString(),
      videoDuration: int.tryParse((json['videoDuration'] ?? '').toString()),
      videoWidth: int.tryParse((json['videoWidth'] ?? '').toString()),
      videoHeight: int.tryParse((json['videoHeight'] ?? '').toString()),
      voiceUrl: json['voiceUrl'] as String?,
      voiceDuration: int.tryParse((json['voiceDuration'] ?? '').toString()),
      isRead: json['read'] == true,
    );
  }

  /// Convert string type to MessageType enum
  MessageType _parseMessageType(String type) {
    switch (type.toLowerCase()) {
      case 'image':
        return MessageType.image;
      case 'video':
        return MessageType.video;
      case 'voice':
        return MessageType.voice;
      case 'text':
      default:
        return MessageType.text;
    }
  }
}
