/// Production [Embedder] backed by the Rust `lifeos_native` crate,
/// generated bindings via `flutter_rust_bridge` + native build via
/// cargokit (D-1.7c per `docs/architecture/lifeos-shell.md` §6.6).
///
/// EmbeddingGemma-300M (ONNX INT8) → 768-d unit vector; fingerprint
/// `'embeddinggemma-300m-onnx-int8-d768'`. Drop-in for [StubEmbedder]:
/// the [MemoryStore] fingerprint discipline (D-1.7b) means swapping
/// in this embedder invalidates Stub-produced vectors automatically.
///
/// Constructor is async — it `await`s both `RustLib.init` (once per
/// app) and the model load (~seconds for ONNX session warm-up).
/// Embedding cost on Apple Silicon CPU + CoreML: ~30–100 ms per
/// call depending on input length.
///
/// **Library loading**: `flutter run` / `flutter build` builds the
/// crate via cargokit (`rust_builder/` Flutter plugin) and bundles
/// the dylib into the standard plugin paths. `RustLib.init()` with
/// no args finds it. The optional [libraryPath] override is only
/// for `flutter test` on desktop (the test harness can't go through
/// the plugin loader) and dev-machine experimentation.
library;

import 'package:naviwealth/core/native/lifeos_native_runtime.dart'
    as native_runtime;
import 'package:naviwealth/src/rust/api/embedder.dart' as frb;

import 'embedder.dart';

/// Thrown when the Rust embedder can't be constructed (missing
/// native library, missing model files, malformed config, etc.).
/// Callers should fall back to [StubEmbedder].
class RustEmbedderUnavailable implements Exception {
  RustEmbedderUnavailable(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() =>
      'RustEmbedderUnavailable: $message${cause == null ? '' : ' ($cause)'}';
}

/// Initialise the FRB runtime against [libraryPath] (or the default
/// cargokit-managed loader when `null`). Idempotent — repeat calls
/// share the domain-neutral runtime's underlying future.
///
/// Throws [RustEmbedderUnavailable] if the dylib can't be loaded.
/// In production (`flutter run` / `flutter build`) pass `null` and
/// let cargokit's plugin path resolution find the bundled lib.
Future<void> initLifeosNativeRuntime({String? libraryPath}) {
  return _initEmbedderRuntime(libraryPath: libraryPath);
}

Future<void> _initEmbedderRuntime({String? libraryPath}) async {
  try {
    await native_runtime.initLifeosNativeRuntime(libraryPath: libraryPath);
  } on Object catch (e) {
    throw RustEmbedderUnavailable(
      'failed to initialise lifeos_native runtime',
      cause: e,
    );
  }
}

class RustGemmaEmbedder implements Embedder {
  RustGemmaEmbedder._(this._inner, this._fingerprint, this._dimension);

  /// Load the embedder from [modelDir]. The directory must contain
  /// the ONNX model + tokenizer/config JSON files. See
  /// `apps/mobile/native/lifeos_native/README.md` for the exact file
  /// list (sourced from the `onnx-community/embeddinggemma-300m-ONNX`
  /// HuggingFace repo).
  ///
  /// [ortDylibPath] points at `libonnxruntime.{dylib,so,dll}`. ORT
  /// is dynamically loaded (not statically linked) to dodge the
  /// duplicate-symbol issue in ORT's prebuilt static archives;
  /// download URLs are in the README. Pass an empty string to use
  /// whatever `ORT_DYLIB_PATH` env var is already set (e.g. tests).
  ///
  /// [libraryPath] is the path to `liblifeos_native.{dylib,so}` —
  /// pass `null` in production; cargokit ensures the lib is on the
  /// plugin path. Only specify this for desktop `flutter test`
  /// runs where the test harness doesn't go through the plugin
  /// loader.
  ///
  /// Throws [RustEmbedderUnavailable] on any failure.
  static Future<RustGemmaEmbedder> load({
    required String modelDir,
    required String ortDylibPath,
    String? libraryPath,
  }) async {
    await initLifeosNativeRuntime(libraryPath: libraryPath);
    try {
      final inner = await frb.GemmaEmbedder.load(
        modelDir: modelDir,
        ortDylibPath: ortDylibPath,
      );
      // dimension() / fingerprint() are `#[frb(sync)]` so they return
      // immediately and we can cache them on the Dart side.
      return RustGemmaEmbedder._(inner, inner.fingerprint(), inner.dimension());
    } on Object catch (e) {
      throw RustEmbedderUnavailable('GemmaEmbedder.load failed', cause: e);
    }
  }

  final frb.GemmaEmbedder _inner;
  final String _fingerprint;
  final int _dimension;
  bool _disposed = false;

  @override
  int get dimension => _dimension;

  @override
  String get fingerprint => _fingerprint;

  @override
  Future<List<double>> embed(String text) async {
    if (_disposed) {
      throw StateError('RustGemmaEmbedder has been disposed');
    }
    try {
      final result = await _inner.embed(text: text);
      // FRB returns Float32List; Embedder contract is List<double>.
      return result.toList(growable: false);
    } on Object catch (e) {
      throw RustEmbedderUnavailable('embed failed', cause: e);
    }
  }

  /// FRB's `RustOpaqueInterface` drops its handle when garbage
  /// collected, but explicit dispose surfaces deterministic
  /// cleanup (useful when swapping embedders at runtime). Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _inner.dispose();
  }
}
