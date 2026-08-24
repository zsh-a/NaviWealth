/// Manifest of model assets the embedder needs at runtime
/// (D-1.7c per `docs/architecture/lifeos-shell.md` §6.6).
///
/// Each [ModelBundle] is a logical group of files that get
/// downloaded together via the in-app installer (Settings →
/// AI Models). The Settings UI iterates registered bundles; capability
/// bootstraps check their own bundle for completeness before loading a native
/// runtime.
///
/// **What's NOT in here**: ONNX Runtime. ORT is a Rust crate
/// dependency built/fetched alongside `liblifeos_native` by
/// `tool/fetch-onnxruntime.sh`, not user-installable data. See
/// `lifeos-shell.md` §6.6 + `discoverBundledOrtDylib`.
///
/// **Cross-domain neutral**: the types don't carry finance- or
/// embedder-specific fields. Embedding and speech recognition both use this
/// installer so downloads remain opt-in and independently removable.
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

/// Optional whole-bundle fallback used when the primary per-file host is not
/// reachable. The archive is transient: only the files declared by the bundle
/// are extracted and retained.
class ModelArchiveSource {
  const ModelArchiveSource({
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    required this.rootDirectory,
  });

  final String url;
  final int sizeBytes;
  final String sha256;
  final String rootDirectory;
}

/// A logical group of files. The bundle is "installed" when every
/// [ModelFile] exists on disk (and verifies, if SHA is known).
class ModelBundle {
  const ModelBundle({
    required this.id,
    required this.displayName,
    required this.description,
    required this.files,
    this.archiveFallback,
  });

  /// Stable id; used as the on-disk subdirectory name and the
  /// Settings UI key. Avoid spaces.
  final String id;

  /// UI label.
  final String displayName;

  /// One-line UI description ("Multilingual sentence embedder, 768-d").
  final String description;

  final List<ModelFile> files;

  /// Official archive mirror used only after a primary file download fails.
  final ModelArchiveSource? archiveFallback;

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

/// True-streaming Mandarin Zipformer Large CTC (INT8).
///
/// The ONNX model is mirrored as an immutable file on Hugging Face, which lets
/// the existing atomic downloader verify the weight without requiring archive
/// extraction. SHA-256 values are the upstream LFS object id for the model and
/// a digest verified from the pinned upstream revision for `tokens.txt`.
const streamingZipformerLargeCtcZhBundleId =
    'streaming-zipformer-large-ctc-zh-int8-2025-06-30';

ModelBundle streamingZipformerLargeCtcZhBundle() {
  const baseUrl =
      'https://huggingface.co/csukuangfj/'
      'sherpa-onnx-streaming-zipformer-ctc-zh-int8-2025-06-30/resolve/main';
  return const ModelBundle(
    id: streamingZipformerLargeCtcZhBundleId,
    displayName: 'Zipformer Large CTC 中文实时语音 (INT8)',
    description: '约 155 MB，普通话真流式端侧识别',
    archiveFallback: ModelArchiveSource(
      url:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
          'asr-models/'
          'sherpa-onnx-streaming-zipformer-ctc-zh-int8-2025-06-30.tar.bz2',
      sizeBytes: 127965713,
      sha256:
          'f2ab7a5deb02717801f6a5b26c751b42f8a2db891b07f5b095e6da7442081448',
      rootDirectory: 'sherpa-onnx-streaming-zipformer-ctc-zh-int8-2025-06-30',
    ),
    files: [
      ModelFile(
        localName: 'model.int8.onnx',
        url: '$baseUrl/model.int8.onnx',
        sizeBytes: 162290887,
        sha256:
            '24ffdc19ba9aaed5a6a9beaede1e087745217d82425cf4041bca0c696661801e',
      ),
      ModelFile(
        localName: 'tokens.txt',
        url: '$baseUrl/tokens.txt',
        sizeBytes: 20628,
        sha256:
            '6193c7ea1c96d0d9a1e9652789b40d13a8a913b434a5451e93158f5a09fd6652',
      ),
    ],
  );
}

// NOTE: there is intentionally no `onnxRuntimeBundle()` function
// here. ORT is fetched at build time by `tool/fetch-onnxruntime.sh`
// and discovered at runtime by `discoverBundledOrtDylib`. Keeping a
// Dart-side manifest for it would just duplicate the version pin and
// trick the UI into showing a downloadable bundle the in-app installer
// can't handle (the upstream archive is a tar of multiple files, not a
// single dylib).
