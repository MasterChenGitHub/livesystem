import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PreparedImage {
  const PreparedImage({
    required this.mainPath,
    required this.thumbPath,
    required this.width,
    required this.height,
    required this.size,
  });

  final String mainPath;
  final String thumbPath;
  final int width;
  final int height;
  final int size;
}

class ImagePreprocessService {
  Future<PreparedImage> prepare(XFile source) async {
    final originalBytes = await source.readAsBytes();
    final size = originalBytes.length;

    final codec = await ui.instantiateImageCodec(originalBytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;

    final tempDir = await getTemporaryDirectory();
    final baseName = DateTime.now().microsecondsSinceEpoch.toString();
    final mainPath = p.join(tempDir.path, '${baseName}_main.jpg');
    final thumbPath = p.join(tempDir.path, '${baseName}_thumb.jpg');

    final mainFile = await FlutterImageCompress.compressAndGetFile(
      source.path,
      mainPath,
      quality: 80,
      minWidth: 1440,
      minHeight: 1440,
      format: CompressFormat.jpeg,
    );

    final thumbFile = await FlutterImageCompress.compressAndGetFile(
      source.path,
      thumbPath,
      quality: 65,
      minWidth: 320,
      minHeight: 320,
      format: CompressFormat.jpeg,
    );

    if (mainFile == null || thumbFile == null) {
      throw Exception('图片压缩失败');
    }

    return PreparedImage(
      mainPath: mainFile.path,
      thumbPath: thumbFile.path,
      width: width,
      height: height,
      size: size,
    );
  }

  Future<void> cleanup(PreparedImage prepared) async {
    await _tryDelete(prepared.mainPath);
    await _tryDelete(prepared.thumbPath);
  }

  Future<void> _tryDelete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }
}
