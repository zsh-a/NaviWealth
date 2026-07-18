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
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

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
  ModelDownloader({Dio? dio})
    : _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));

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

    await _downloadToPath(
      url: file.url,
      partialPath: partialPath,
      onProgress: onProgress,
      cancel: cancel,
    );

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

  /// Downloads and extracts a verified official tar.bz2 fallback for [bundle].
  /// The compressed archive and intermediate tar are always deleted; only the
  /// manifest-declared files are committed to [destDir].
  Future<void> downloadArchiveFallback({
    required ModelBundle bundle,
    required String destDir,
    void Function(int received, int? total)? onProgress,
    DownloadCancellation? cancel,
  }) async {
    final source = bundle.archiveFallback;
    if (source == null) {
      throw ArgumentError.value(bundle.id, 'bundle', 'has no archive fallback');
    }

    final dir = Directory(destDir);
    if (!dir.existsSync()) await dir.create(recursive: true);
    await cleanupTransientFiles(bundle: bundle, destDir: destDir);
    final archivePath = p.join(dir.path, '.${bundle.id}.fallback.tar.bz2');
    final tarPath = '$archivePath.tar';
    final archiveFile = File(archivePath);
    final tarFile = File(tarPath);
    final partialOutputs = <String, String>{
      for (final file in bundle.files)
        '${source.rootDirectory}/${file.localName}': p.join(
          dir.path,
          '${file.localName}.partial',
        ),
    };

    try {
      await _downloadToPath(
        url: source.url,
        partialPath: archivePath,
        onProgress: onProgress,
        cancel: cancel,
      );
      final archiveDigest = await _sha256OfFile(archiveFile);
      if (archiveDigest.toLowerCase() != source.sha256.toLowerCase()) {
        throw ChecksumMismatch(expected: source.sha256, actual: archiveDigest);
      }
      if (cancel?.isCancelled ?? false) {
        throw StateError('download cancelled');
      }

      await Isolate.run(
        () => _extractTarBz2Files(
          archivePath: archivePath,
          tarPath: tarPath,
          partialOutputs: partialOutputs,
        ),
      );

      for (final file in bundle.files) {
        final partial = File(p.join(dir.path, '${file.localName}.partial'));
        await _verifyManifestFile(file, partial);
      }
      if (cancel?.isCancelled ?? false) {
        throw StateError('download cancelled');
      }

      for (final file in bundle.files) {
        final finalFile = File(p.join(dir.path, file.localName));
        final partial = File('${finalFile.path}.partial');
        if (finalFile.existsSync()) await finalFile.delete();
        await partial.rename(finalFile.path);
      }
    } finally {
      if (archiveFile.existsSync()) await archiveFile.delete();
      if (tarFile.existsSync()) await tarFile.delete();
      for (final partialPath in partialOutputs.values) {
        final partial = File(partialPath);
        if (partial.existsSync()) await partial.delete();
      }
    }
  }

  /// Removes interrupted primary/archive downloads from an earlier process.
  /// Completed model files are never touched.
  Future<void> cleanupTransientFiles({
    required ModelBundle bundle,
    required String destDir,
  }) async {
    final paths = <String>[
      p.join(destDir, '.${bundle.id}.fallback.tar.bz2'),
      p.join(destDir, '.${bundle.id}.fallback.tar.bz2.tar'),
      for (final file in bundle.files)
        p.join(destDir, '${file.localName}.partial'),
    ];
    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
  }

  Future<void> _downloadToPath({
    required String url,
    required String partialPath,
    void Function(int received, int? total)? onProgress,
    DownloadCancellation? cancel,
  }) async {
    final partialFile = File(partialPath);
    if (partialFile.existsSync()) await partialFile.delete();
    if (cancel?.isCancelled ?? false) {
      throw StateError('download cancelled');
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
        url,
        partialPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          onProgress?.call(received, total <= 0 ? null : total);
        },
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          // 24h overall budget for huge models on slow networks.
          receiveTimeout: const Duration(hours: 24),
        ),
      );
      if (cancel?.isCancelled ?? false) {
        throw StateError('download cancelled');
      }
    } on Object catch (error) {
      if (partialFile.existsSync()) await partialFile.delete();
      if (error is DioException && CancelToken.isCancel(error)) {
        throw StateError('download cancelled');
      }
      rethrow;
    } finally {
      await cancelWatcher?.cancel();
      if ((cancel?.isCancelled ?? false) && partialFile.existsSync()) {
        await partialFile.delete();
      }
    }
  }

  static Future<void> _verifyManifestFile(ModelFile manifest, File file) async {
    if (!file.existsSync()) {
      throw StateError('archive is missing ${manifest.localName}');
    }
    final expectedSize = manifest.sizeBytes;
    if (expectedSize != null && await file.length() != expectedSize) {
      throw StateError('archive size mismatch for ${manifest.localName}');
    }
    final expectedSha = manifest.sha256;
    if (expectedSha != null) {
      final actual = await _sha256OfFile(file);
      if (actual.toLowerCase() != expectedSha.toLowerCase()) {
        throw ChecksumMismatch(expected: expectedSha, actual: actual);
      }
    }
  }

  /// Streaming SHA-256 hash so we don't slurp 300 MB into memory.
  /// crypto's `Converter.bind` consumes the file's byte stream and
  /// emits a single [Digest] at end-of-stream.
  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}

void _extractTarBz2Files({
  required String archivePath,
  required String tarPath,
  required Map<String, String> partialOutputs,
}) {
  final compressed = InputFileStream(archivePath);
  final tarOutput = OutputFileStream(tarPath);
  try {
    final valid = BZip2Decoder().decodeStream(
      compressed,
      tarOutput,
      verify: true,
    );
    if (!valid) throw const FormatException('invalid bzip2 model archive');
  } finally {
    tarOutput.closeSync();
    compressed.closeSync();
  }

  final extracted = <String>{};
  final tarInput = InputFileStream(tarPath);
  try {
    TarDecoder().decodeStream(
      tarInput,
      verify: true,
      callback: (entry) {
        final outputPath = partialOutputs[entry.name];
        if (outputPath == null || !entry.isFile) return;
        final output = OutputFileStream(outputPath);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
          entry.clear();
        }
        extracted.add(entry.name);
      },
    );
  } finally {
    tarInput.closeSync();
  }

  final missing = partialOutputs.keys.toSet().difference(extracted);
  if (missing.isNotEmpty) {
    throw FormatException('model archive is missing: ${missing.join(', ')}');
  }
}
