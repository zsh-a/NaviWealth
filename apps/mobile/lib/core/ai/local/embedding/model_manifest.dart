/// Manifest of model assets the embedder needs at runtime
/// (D-1.7c per `docs/lifeos-shell.md` §6.6).
///
/// Each [ModelBundle] is a logical group of files that get
/// downloaded together via the in-app installer (Settings →
/// AI Models). The Settings UI iterates registered bundles; the
/// bootstrap auto-discovery checks each bundle for completeness
/// before electing to use the Rust embedder over the stub.
///
/// **What's NOT in here**: ONNX Runtime. ORT is a Rust crate
/// dependency built/fetched alongside `liblifeos_native` by
/// `tool/fetch-onnxruntime.sh`, not user-installable data. See
/// `lifeos-shell.md` §6.6 + the `_discoverBundledOrtDylib`
/// resolver in `bootstrap.dart`.
///
/// **Cross-domain neutral**: lives in `embedding/` because that's
/// the only consumer today, but the types don't carry finance- or
/// embedder-specific fields. A future HealthOS / TimeOS asset (e.g.
/// a speech recogniser model) can reuse the same types.
library;

/// A single file inside a [ModelBundle]. Downloaded one-by-one with
/// per-file progress / verification.
class ModelFile {
  const ModelFile({
    required this.localName,
    required this.url,
    this.sizeBytes,
    this.sha256,
  });

  /// Filename on local disk (under the bundle's install dir). The
  /// embedder loader expects exactly these names — keep stable.
  final String localName;

  /// Public HTTPS download URL. The downloader streams from here
  /// directly; no proxy / hub lookup.
  final String url;

  /// Expected file size in bytes, if known. Drives the UI progress
  /// estimate when the server doesn't send Content-Length.
  final int? sizeBytes;

  /// Optional SHA-256 (hex). When present the downloader verifies
  /// after writing; mismatch deletes the file and surfaces an error.
  final String? sha256;
}

/// A logical group of files. The bundle is "installed" when every
/// [ModelFile] exists on disk (and verifies, if SHA is known).
class ModelBundle {
  const ModelBundle({
    required this.id,
    required this.displayName,
    required this.description,
    required this.files,
  });

  /// Stable id; used as the on-disk subdirectory name and the
  /// Settings UI key. Avoid spaces.
  final String id;

  /// UI label.
  final String displayName;

  /// One-line UI description ("Multilingual sentence embedder, 768-d").
  final String description;

  final List<ModelFile> files;

  /// Sum of [ModelFile.sizeBytes] across files. `null` when any file
  /// has unknown size.
  int? get totalSizeBytes {
    var sum = 0;
    for (final f in files) {
      final s = f.sizeBytes;
      if (s == null) return null;
      sum += s;
    }
    return sum;
  }
}

// ---------------------------------------------------------------------
// Concrete bundles (the in-app installer downloads these)
// ---------------------------------------------------------------------

/// EmbeddingGemma-300M (ONNX INT8 + tokenizer). Sourced from
/// `onnx-community/embeddinggemma-300m-ONNX` on HuggingFace.
///
/// The model weights are split across two files: `model_quantized.onnx`
/// (graph topology, ~568 KB) and `model_quantized.onnx_data` (external
/// weights blob, ~309 MB). ONNX's external-data format requires both
/// to sit in the same directory with their relative path intact —
/// `pick_onnx_path` + `with_external_initializer` in `embedder.rs`
/// handle the wiring.
///
/// Sizes are exact byte counts pulled from the HF web UI as of the
/// model's most recent revision; minor drift on re-uploads is
/// tolerated by `ModelInstallPaths.isComplete`'s ±5% slack. SHAs
/// are intentionally omitted because upstream doesn't publish them
/// per file; HTTPS provides transport integrity.
ModelBundle embeddingGemmaBundle() {
  const baseUrl =
      'https://huggingface.co/onnx-community/embeddinggemma-300m-ONNX/resolve/main';
  return const ModelBundle(
    id: 'embeddinggemma-300m-onnx',
    displayName: 'EmbeddingGemma 300M (ONNX INT8)',
    description: '多语言 768-d 句向量模型,本地推理',
    files: [
      ModelFile(
        localName: 'model_quantized.onnx',
        url: '$baseUrl/onnx/model_quantized.onnx',
        sizeBytes: 582272, // 568 KB — graph topology only
      ),
      ModelFile(
        localName: 'model_quantized.onnx_data',
        url: '$baseUrl/onnx/model_quantized.onnx_data',
        sizeBytes: 323854336, // 309 MB — external weights blob
      ),
      ModelFile(
        localName: 'tokenizer.json',
        url: '$baseUrl/tokenizer.json',
        sizeBytes: 20 * 1024 * 1024 + 300 * 1024, // ~20.3 MB
      ),
      ModelFile(
        localName: 'config.json',
        url: '$baseUrl/config.json',
        sizeBytes: 1770,
      ),
      ModelFile(
        localName: 'special_tokens_map.json',
        url: '$baseUrl/special_tokens_map.json',
        sizeBytes: 662,
      ),
      ModelFile(
        localName: 'tokenizer_config.json',
        url: '$baseUrl/tokenizer_config.json',
        sizeBytes: 1160 * 1024, // ~1.16 MB
      ),
    ],
  );
}

// NOTE: there is intentionally no `onnxRuntimeBundle()` function
// here. ORT is fetched at build time by `tool/fetch-onnxruntime.sh`
// and discovered at runtime by `_discoverBundledOrtDylib` in
// `bootstrap.dart`. Keeping a Dart-side manifest for it would just
// duplicate the version pin and trick the UI into showing a
// downloadable bundle the in-app installer can't handle (the
// upstream archive is a tar of multiple files, not a single dylib).
