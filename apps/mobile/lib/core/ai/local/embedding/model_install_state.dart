/// Per-bundle install-state controller (D-1.7c).
///
/// Wraps [ModelDownloader] + on-disk state so the Settings UI gets
/// a single observable for "what's the current state of this
/// bundle". Methods to mutate state:
///
/// - [ModelInstallController.install] — start downloading missing files
/// - [ModelInstallController.cancel]  — abort the in-flight install
/// - [ModelInstallController.delete]  — remove all of the bundle's files
///
/// All UI-facing state lives in [ModelBundleState] (immutable
/// snapshot). The controller emits a new snapshot on every change.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'model_downloader.dart';
import 'model_install_paths.dart';
import 'model_manifest.dart';

enum ModelFileStatus {
  /// File is not on disk and no download is in flight.
  notInstalled,

  /// File is being downloaded right now.
  downloading,

  /// File is fully on disk and (if SHA known) verified.
  installed,

  /// Last attempt errored; [ModelFileState.error] explains.
  failed,
}

/// Immutable per-file snapshot. The controller rebuilds the whole
/// list on every update — small bundle sizes make this cheap.
class ModelFileState {
  const ModelFileState({
    required this.file,
    required this.status,
    this.bytesDownloaded = 0,
    this.error,
  });

  final ModelFile file;
  final ModelFileStatus status;
  final int bytesDownloaded;
  final String? error;

  /// `0..1` ratio of bytes received vs expected. Returns `null` when
  /// expected size is unknown.
  double? get progress {
    final total = file.sizeBytes;
    if (total == null || total <= 0) return null;
    return (bytesDownloaded / total).clamp(0.0, 1.0);
  }

  ModelFileState copyWith({
    ModelFileStatus? status,
    int? bytesDownloaded,
    String? error,
    bool clearError = false,
  }) =>
      ModelFileState(
        file: file,
        status: status ?? this.status,
        bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Immutable bundle snapshot.
class ModelBundleState {
  const ModelBundleState({
    required this.bundle,
    required this.installDir,
    required this.files,
    this.isInstalling = false,
  });

  final ModelBundle bundle;
  final String installDir;
  final List<ModelFileState> files;
  final bool isInstalling;

  bool get isInstalled =>
      files.every((f) => f.status == ModelFileStatus.installed);

  /// Aggregate progress across all files in the bundle. Returns
  /// `null` if any file has unknown size; otherwise weighted by
  /// individual file sizes.
  double? get aggregateProgress {
    var total = 0;
    var received = 0;
    for (final f in files) {
      final size = f.file.sizeBytes;
      if (size == null) return null;
      total += size;
      if (f.status == ModelFileStatus.installed) {
        received += size;
      } else if (f.status == ModelFileStatus.downloading) {
        received += f.bytesDownloaded;
      }
    }
    if (total == 0) return 0;
    return (received / total).clamp(0.0, 1.0);
  }

  ModelBundleState copyWith({
    List<ModelFileState>? files,
    bool? isInstalling,
  }) =>
      ModelBundleState(
        bundle: bundle,
        installDir: installDir,
        files: files ?? this.files,
        isInstalling: isInstalling ?? this.isInstalling,
      );
}

class ModelInstallController extends AsyncNotifier<ModelBundleState> {
  ModelInstallController(this._bundle);

  final ModelBundle _bundle;

  DownloadCancellation? _cancellation;
  ModelDownloader? _downloader;
  ModelInstallPaths? _paths;

  @override
  Future<ModelBundleState> build() async {
    final paths = await ref.watch(modelInstallPathsProvider.future);
    _paths = paths;
    _downloader ??= ModelDownloader();
    final dir = paths.dirForBundle(_bundle);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final fileStates = <ModelFileState>[
      for (final f in _bundle.files) await _scanFileState(f, dir.path),
    ];
    return ModelBundleState(
      bundle: _bundle,
      installDir: dir.path,
      files: fileStates,
    );
  }

  Future<ModelFileState> _scanFileState(
    ModelFile file,
    String dirPath,
  ) async {
    final disk = File('$dirPath/${file.localName}');
    if (!disk.existsSync()) {
      return ModelFileState(file: file, status: ModelFileStatus.notInstalled);
    }
    final size = await disk.length();
    final expected = file.sizeBytes;
    final ok = expected == null || (size - expected).abs() <= expected * 0.05;
    return ModelFileState(
      file: file,
      status: ok ? ModelFileStatus.installed : ModelFileStatus.failed,
      bytesDownloaded: size,
      error: ok ? null : 'on-disk size $size bytes ≠ manifest $expected',
    );
  }

  /// Start downloading every missing/failed file. Idempotent: files
  /// already installed are skipped. Concurrent calls bail (only one
  /// install in flight per bundle).
  Future<void> install() async {
    final current = state.value;
    if (current == null || current.isInstalling) return;

    final paths = _paths;
    final downloader = _downloader;
    if (paths == null || downloader == null) return;

    final cancellation = DownloadCancellation();
    _cancellation = cancellation;
    state = AsyncData(current.copyWith(isInstalling: true));

    try {
      for (var i = 0; i < current.files.length; i++) {
        if (cancellation.isCancelled) break;
        final fileState = state.value!.files[i];
        if (fileState.status == ModelFileStatus.installed) continue;

        _updateFile(
          i,
          fileState.copyWith(
            status: ModelFileStatus.downloading,
            bytesDownloaded: 0,
            clearError: true,
          ),
        );

        try {
          await downloader.download(
            file: fileState.file,
            destDir: current.installDir,
            cancel: cancellation,
            onProgress: (received, _) {
              final latest = state.value!.files[i];
              _updateFile(i, latest.copyWith(bytesDownloaded: received));
            },
          );
          _updateFile(
            i,
            state.value!.files[i].copyWith(
              status: ModelFileStatus.installed,
              clearError: true,
            ),
          );
        } on Object catch (e) {
          _updateFile(
            i,
            state.value!.files[i].copyWith(
              status: ModelFileStatus.failed,
              error: e.toString(),
            ),
          );
          if (e is StateError && e.message.contains('cancelled')) {
            break;
          }
        }
      }
    } finally {
      final after = state.value!;
      state = AsyncData(after.copyWith(isInstalling: false));
      _cancellation = null;
    }
  }

  /// Abort the in-flight install. Files already on disk stay; the
  /// in-progress file gets its .partial deleted (downloader handles
  /// cleanup). UI should refresh after this resolves.
  void cancel() {
    _cancellation?.cancel();
  }

  /// Delete every file in the bundle from disk. Stub-embedder
  /// fallback kicks back in on next bootstrap.
  Future<void> delete() async {
    final paths = _paths;
    final current = state.value;
    if (paths == null || current == null) return;
    final dir = paths.dirForBundle(current.bundle);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
    final newFiles = <ModelFileState>[
      for (final f in current.bundle.files)
        ModelFileState(file: f, status: ModelFileStatus.notInstalled),
    ];
    state = AsyncData(current.copyWith(files: newFiles, isInstalling: false));
  }

  void _updateFile(int index, ModelFileState newState) {
    final current = state.value;
    if (current == null) return;
    final updated = List<ModelFileState>.of(current.files);
    updated[index] = newState;
    state = AsyncData(current.copyWith(files: updated));
  }
}

/// Per-bundle install controller. The Settings UI listens on this
/// for the bundles it cares about (EmbeddingGemma + ORT).
final modelInstallProvider = AsyncNotifierProvider.autoDispose
    .family<ModelInstallController, ModelBundleState, ModelBundle>(
      ModelInstallController.new,
    );

/// Static list of bundles the app knows how to install. The UI
/// iterates this. Extending: add another entry (e.g. for a future
/// Whisper model) — no other touchpoints needed.
final knownModelBundlesProvider = Provider<List<ModelBundle>>((ref) {
  final ort = onnxRuntimeBundle();
  return [embeddingGemmaBundle(), ?ort];
});
