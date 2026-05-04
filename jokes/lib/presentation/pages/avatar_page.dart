import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/datasources/token_storage.dart';
import '../../services/message_service.dart';

class AvatarPage extends StatefulWidget {
  const AvatarPage({super.key, required this.currentAvatar});

  final String currentAvatar;

  @override
  State<AvatarPage> createState() => _AvatarPageState();
}

class _AvatarPageState extends State<AvatarPage> {
  final ImagePicker _picker = ImagePicker();
  String? _pickedPath;
  bool _uploading = false;

  Future<void> _pickFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1280,
    );
    if (file == null) return;
    if (!mounted) return;
    setState(() {
      _pickedPath = file.path;
    });
    await _uploadAvatar();
  }

  Future<void> _uploadAvatar() async {
    if (_pickedPath == null || _pickedPath!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先从相册选择头像')));
      return;
    }

    setState(() => _uploading = true);
    try {
      final dio = context.read<Dio>();
      final storage = context.read<TokenStorage>();
      final messageService = MessageService(dio: dio, tokenStorage: storage);

      final upload = await messageService.uploadFileDirectToOss(
        filePath: _pickedPath!,
        fileType: 'image',
      );
      final avatarUrl = upload['url']?.toString() ?? '';
      if (avatarUrl.isEmpty) {
        throw Exception('上传成功但未返回头像地址');
      }

      final response = await dio.post<Map<String, dynamic>>(
        '/auth/profile/avatar',
        data: {'avatarUrl': avatarUrl},
      );
      final body = response.data;
      if (response.statusCode != 200 || body == null) {
        throw Exception('更新头像失败');
      }

      await storage.saveAvatar(avatarUrl);
      if (!mounted) return;
      Navigator.of(context).pop(avatarUrl);
    } on DioException catch (e) {
      final msg = e.response?.data is Map<String, dynamic>
          ? (e.response?.data['message'] ?? e.response?.data['error'])
                ?.toString()
          : null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? '上传失败，请稍后重试')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPicked = _pickedPath != null && _pickedPath!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('头像')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            CircleAvatar(
              radius: 72,
              backgroundImage: hasPicked
                  ? FileImage(File(_pickedPath!))
                  : (widget.currentAvatar.isNotEmpty
                        ? NetworkImage(widget.currentAvatar)
                        : null),
              child: !hasPicked && widget.currentAvatar.isEmpty
                  ? const Icon(Icons.person, size: 72)
                  : null,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _pickFromGallery,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: Text(_uploading ? '上传中…' : '从相册选择并自动上传'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
