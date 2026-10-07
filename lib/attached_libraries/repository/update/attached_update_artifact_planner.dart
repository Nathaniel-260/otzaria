import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';

/// תקרת החלון של zstd (2^31): prefix גדול מזה אינו ניתן להצגה לפענוח.
const int kMaxDeltaBaseBytes = 2 * 1024 * 1024 * 1024;

/// מה יורד בפועל: [delta] לא null ⇒ [artifact] הוא תיקון שיוחל על המסד המותקן.
class AttachedUpdatePlan {
  const AttachedUpdatePlan(this.artifact, {this.delta});

  final AttachedUpdateArtifact artifact;
  final AttachedUpdateDelta? delta;

  bool get isDelta => delta != null;
}

/// בוחר בין הקובץ המלא לתיקון דלתא. כל ספק — מידות, גרסה, מכונה 32 סיביות —
/// מחזיר את הקובץ המלא בלי להציג שגיאה למשתמש. הבסיס אינו מוחשב ב-sha256
/// (דקות על גיגה-בייט): דלתא על בסיס שונה נכשלת באימות הפלט מול המניפסט
/// החתום, והשירות חוזר אז לקובץ המלא.
class AttachedUpdateArtifactPlanner {
  const AttachedUpdateArtifactPlanner({
    this.pointerSize,
    this.maxBaseBytes = kMaxDeltaBaseBytes,
  });

  /// דריסה לבדיקות של רוחב המצביע (8 = 64 סיביות).
  final int? pointerSize;

  /// גודל הקובץ המותקן שעדיין אפשר להשתמש בו כ-prefix.
  final int maxBaseBytes;

  Future<AttachedUpdatePlan> plan(
    AttachedUpdateManifest manifest, {
    required String installedPath,
    required int installedDbVersion,
  }) async {
    final full = AttachedUpdatePlan(manifest.full);
    try {
      if ((pointerSize ?? sizeOf<Pointer>()) != 8) return full;
      final candidates =
          manifest.deltas
              .where(
                (d) =>
                    d.fromDbVersion == installedDbVersion &&
                    d.artifact.compression ==
                        AttachedUpdateCompression.zstdPatch &&
                    d.artifact.compressedSize < manifest.full.compressedSize,
              )
              .toList()
            ..sort(
              (a, b) => a.artifact.compressedSize.compareTo(
                b.artifact.compressedSize,
              ),
            );
      if (candidates.isEmpty) return full;
      final stat = await FileStat.stat(installedPath);
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          stat.size > maxBaseBytes) {
        return full;
      }
      final delta = candidates.first;
      return AttachedUpdatePlan(delta.artifact, delta: delta);
    } catch (e) {
      debugPrint('[AttachedUpdates] delta planning failed: $e');
      return full;
    }
  }
}
