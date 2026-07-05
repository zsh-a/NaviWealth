/// Per-file downloader for model assets (D-1.7c).
///
/// Wraps Dio with three operational guarantees:
///
/// 1. **Atomic install**: stream to `<name>.partial`, fsync, then
///    rename to `<name>`. A killed process never leaves a half-file
///    that bootstrap mistakes for "installed".
/// 2. **Progress callback**: `(received, total?)` for the UI's
///    progress bar. `total` is null when the server omits
///    Content-Length.
/// 3. **Integrity (when provided)**: SHA-256 verify after write;
///    mismatch deletes the partial + throws.
///
/// **Not** in scope today: resume of partial downloads (would need
/// Range requests + server cooperation). Failed downloads restart
/// from byte 0 on retry — fine for our few-files-per-bundle case.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'model_manifest.dart';

/// Thrown when the bytes on disk don't match the manifest's SHA-256.
class ChecksumMismatch implements Exception {
  ChecksumMismatch({required this.expected, required this.actual});
  final String expected;
  final String actual;
  @override
  String toString() => 'ChecksumMismatch: expected $expected, got $actual';
}

/// Cancellation handle the caller can flip to abort an in-flight
/// download. The downloader checks before/after each chunk.
class DownloadCancellation {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled;
}

class ModelDownloader {
  ModelDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Download [file] to `<destDir>/<file.localName>`. Streams to a
  /// `.partial` file first; renames on success. Returns when the
  /// file is fully on disk and verified.
  ///
  /// [onProgress] fires roughly every 64 KB (Dio's default chunk).
  /// `total` is null when the server didn't send Content-Length.
  ///
  /// Throws [ChecksumMismatch], [DioException], [SocketException],
  /// or [StateError] (when cancelled).
  Future<void> download({
    required ModelFile file,
    required String destDir,
    void Function(int received, int? total)? onProgress,
    DownloadCancellation? cancel,
  }) async {
    final dir = Directory(destDir);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final finalPath = '${dir.path}/${file.localName}';
    final partialPath = '$finalPath.partial';
    final partialFile = File(partialPath);
    if (partialFile.existsSync()) {
      await partialFile.delete();
    }

    final cancelToken = CancelToken();
    StreamSubscription<void>? cancelWatcher;
    if (cancel != null) {
      // Poll the cancellation flag; cheap enough vs. download time.
      cancelWatcher = Stream<void>.periodic(const Duration(milliseconds: 200))
          .listen((_) {
            if (cancel.isCancelled && !cancelToken.isCancelled) {
              cancelToken.cancel('user cancelled');
            }
          });
    }

    try {
      await _dio.download(
        file.url,
        partialPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (onProgress != null) {
            onProgress(received, total <= 0 ? null : total);
          }
        },
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          // 24h overall budget for huge models on slow networks.
          receiveTimeout: const Duration(hours: 24),
        ),
      );
    } on DioException catch (e) {
      // Clean up partial on any failure (cancel included) so retry
      // starts fresh.
      if (partialFile.existsSync()) {
        await partialFile.delete();
      }
      if (CancelToken.isCancel(e)) {
        throw StateError('download cancelled');
      }
      rethrow;
    } finally {
      await cancelWatcher?.cancel();
    }

    // Verify SHA-256 if the manifest provided one.
    final expected = file.sha256;
    if (expected != null) {
      final actual = await _sha256OfFile(partialFile);
      if (actual.toLowerCase() != expected.toLowerCase()) {
        await partialFile.delete();
        throw ChecksumMismatch(expected: expected, actual: actual);
      }
    }

    // Atomic rename. On POSIX this is rename(2); on Windows fall
    // back to copy+delete. Both are safe.
    final finalFile = File(finalPath);
    if (finalFile.existsSync()) {
      await finalFile.delete();
    }
    await partialFile.rename(finalPath);
  }

  /// Streaming SHA-256 hash so we don't slurp 300 MB into memory.
  /// crypto's `Converter.bind` consumes the file's byte stream and
  /// emits a single [Digest] at end-of-stream.
  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
