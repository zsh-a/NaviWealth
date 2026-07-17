import 'dart:async';

import 'package:flutter_riverpod/misc.dart';

import '../../core/ai/local/embedding/embedder.dart';
import '../../core/ai/local/embedding/embedder_path_resolution.dart';
import '../../core/ai/local/embedding/rust_gemma_embedder.dart';
import '../../core/ai/local/memory/providers.dart' as memory_providers;
import '../../core/config/providers.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/providers.dart';

/// Resolves model paths only when Memory Runtime is first requested.
///
/// Path-provider and filesystem checks used to happen before `runApp()`, even
/// when the user never opened an AI surface. The FutureProvider boundary is
/// already asynchronous, so path discovery and native model warm-up belong
/// behind it.
Override lazyEmbedderProviderOverride() {
  return memory_providers.embedderProvider.overrideWith((ref) async {
    final logger = ref.read(loggerProvider);
    EmbedderPathResolution paths;
    try {
      paths = await resolveEmbedderPaths(ref.watch(appConfigProvider));
    } on Object catch (error, stackTrace) {
      logger.w(
        'Rust embedder path resolution failed; using StubEmbedder',
        error: error,
        stackTrace: stackTrace,
      );
      return StubEmbedder();
    }

    if (!paths.isComplete) {
      logger.i(
        'Rust embedder not configured; using StubEmbedder '
        '(missing: ${paths.missingInputs.join(', ')})',
      );
      return StubEmbedder();
    }
    logger.i(
      'Rust embedder path resolution complete '
      '(modelDir=${paths.modelDir}, ortDylibPath=${paths.ortDylibPath}, '
      'libraryPath=${paths.libraryPath ?? '<plugin-loader>'})',
    );
    return _loadRustEmbedderOrFallback(
      modelDir: paths.modelDir,
      ortDylibPath: paths.ortDylibPath,
      libraryPath: paths.libraryPath,
      logger: logger,
    );
  });
}

Future<Embedder> _loadRustEmbedderOrFallback({
  required String modelDir,
  required String ortDylibPath,
  required String? libraryPath,
  required AppLogger logger,
}) async {
  final started = Stopwatch()..start();
  logger.i(
    'Rust embedder loading started '
    '(modelDir=$modelDir, ortDylibPath=$ortDylibPath, '
    'libraryPath=${libraryPath ?? '<plugin-loader>'})',
  );
  try {
    final embedder = await RustGemmaEmbedder.load(
      modelDir: modelDir,
      ortDylibPath: ortDylibPath,
      libraryPath: libraryPath,
    ).timeout(const Duration(seconds: 90));
    logger.i(
      'Rust embedder loaded (${embedder.fingerprint}, '
      'dim=${embedder.dimension}, elapsed=${started.elapsed})',
    );
    return embedder;
  } on TimeoutException catch (error, stackTrace) {
    logger.w(
      'Rust embedder load timed out; falling back to StubEmbedder '
      '(elapsed=${started.elapsed})',
      error: error,
      stackTrace: stackTrace,
    );
  } on RustEmbedderUnavailable catch (error, stackTrace) {
    logger.w(
      'Rust embedder unavailable; falling back to StubEmbedder '
      '(elapsed=${started.elapsed})',
      error: error,
      stackTrace: stackTrace,
    );
  } on Object catch (error, stackTrace) {
    logger.w(
      'Rust embedder load failed unexpectedly; falling back to StubEmbedder '
      '(elapsed=${started.elapsed})',
      error: error,
      stackTrace: stackTrace,
    );
  }
  return StubEmbedder();
}
