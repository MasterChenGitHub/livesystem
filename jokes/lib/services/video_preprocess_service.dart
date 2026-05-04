import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

class VideoThumbnail {
  final String path; // Thumbnail file path
  final int width;
  final int height;

  VideoThumbnail({
    required this.path,
    required this.width,
    required this.height,
  });
}

class PreparedVideo {
  final String videoPath;
  final String? thumbPath;
  final int duration; // milliseconds
  final int width;
  final int height;
  final int size; // bytes
  final int? videoSize; // after compression (if applicable)

  PreparedVideo({
    required this.videoPath,
    this.thumbPath,
    required this.duration,
    required this.width,
    required this.height,
    required this.size,
    this.videoSize,
  });
}

class VideoPreprocessService {
  /// Prepare video for upload:
  /// 1. Extract first frame as thumbnail
  /// 2. Optionally compress video (for large files)
  /// 3. Return video path + thumb path + metadata
  Future<PreparedVideo> prepare(String videoPath) async {
    try {
      // Get video info (duration, dimensions, size)
      final info = await VideoCompress.getMediaInfo(videoPath);
      final duration = info.duration ?? 0;
      final width = info.width ?? 0;
      final height = info.height ?? 0;
      final size = File(videoPath).lengthSync();

      // Extract first frame as thumbnail
      final thumbPath = await _extractThumbnail(videoPath);

      // Optionally compress if > 100MB
      String finalVideoPath = videoPath;
      int? compressedSize;
      if (size > 100 * 1024 * 1024) {
        // Compress to H.264, 720p, 2Mbps
        final result = await VideoCompress.compressVideo(
          videoPath,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
        if (result != null) {
          finalVideoPath = result.file!.path;
          compressedSize = result.file!.lengthSync();
        }
      }

      return PreparedVideo(
        videoPath: finalVideoPath,
        thumbPath: thumbPath,
        duration: duration.toInt(),
        width: width.toInt(),
        height: height.toInt(),
        size: size,
        videoSize: compressedSize,
      );
    } catch (e) {
      throw Exception('Video preprocessing failed: $e');
    }
  }

  /// Extract first frame as thumbnail and compress it
  Future<String?> _extractThumbnail(String videoPath) async {
    try {
      // Extract first frame (0ms)
      final file = await VideoCompress.getFileThumbnail(
        videoPath,
        quality: 80,
      );

      final tempDir = await getTemporaryDirectory();
      final thumbFile = File(
        '${tempDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      // Compress thumbnail to max 320x320
      final compressed = await FlutterImageCompress.compressAndGetFile(
        file.path,
        thumbFile.path,
        quality: 65,
        minHeight: 320,
        minWidth: 320,
      );

      return compressed?.path;
    } catch (e) {
      rethrow;
    }
  }

  /// Cleanup temporary files
  Future<void> cleanup(PreparedVideo prepared) async {
    try {
      if (prepared.thumbPath != null) {
        await File(prepared.thumbPath!).delete();
      }
      // Don't delete original video
    } catch (e) {
      rethrow;
    }
  }
}
