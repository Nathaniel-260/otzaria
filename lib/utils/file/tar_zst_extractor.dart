import 'package:otzaria/utils/file/zstd_stream_extractor.dart';

/// מחלץ ארכיון tar.zst לתיקיית היעד בזרימה אחת (zstd → tar), בלי קובץ tar
/// זמני — שהיה מכפיל את המקום הנדרש בדיסק.
Future<void> extractTarZstToDir(
  String archivePath,
  String outputDir, {
  void Function(double progress)? onProgress,
}) => ZstdStreamExtractor.extractTarToDir(
  archivePath,
  outputDir,
  onProgress: onProgress,
);
