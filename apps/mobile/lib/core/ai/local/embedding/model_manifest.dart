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

/// True-streaming Mandarin Zipformer transducer (14M, INT8).
///
/// The ONNX files are mirrored as individual immutable files on Hugging Face,
/// which lets the existing atomic downloader verify every weight without
/// adding an archive extraction dependency. SHA-256 values are the upstream
/// LFS object ids for the three models; `tokens.txt` was verified from the
/// pinned upstream revision.
ModelBundle streamingZipformerZhBundle() {
  const baseUrl =
      'https://huggingface.co/csukuangfj/'
      'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23/resolve/main';
  return const ModelBundle(
    id: 'streaming-zipformer-zh-14m-2023-02-23',
    displayName: 'Zipformer 中文实时语音 (INT8)',
    description: '约 25 MB，普通话真流式端侧识别',
    archiveFallback: ModelArchiveSource(
      url:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
          'asr-models/'
          'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23.tar.bz2',
      sizeBytes: 74004050,
      sha256:
          '2cbd71b640d9c37d3784f29367333a4577b0398b62e9deeed418170b081cba8b',
      rootDirectory: 'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23',
    ),
    files: [
      ModelFile(
        localName: 'encoder-epoch-99-avg-1.int8.onnx',
        url: '$baseUrl/encoder-epoch-99-avg-1.int8.onnx',
        sizeBytes: 21621684,
        sha256:
            '1c556ea57cec304e55ec4b72e52c1cc098bb01476ed7d90f3de939fe126487b1',
      ),
      ModelFile(
        localName: 'decoder-epoch-99-avg-1.int8.onnx',
        url: '$baseUrl/decoder-epoch-99-avg-1.int8.onnx',
        sizeBytes: 1888682,
        sha256:
            '22f123bb8cba9b38974b3df18a3f45e7081f4985ebb2e075d9f21f618c468bbf',
      ),
      ModelFile(
        localName: 'joiner-epoch-99-avg-1.int8.onnx',
        url: '$baseUrl/joiner-epoch-99-avg-1.int8.onnx',
        sizeBytes: 1795562,
        sha256:
            'a7cf9d82757bdcf786059454495a9ca95e4bd7347f72473fc08d794475c36169',
      ),
      ModelFile(
        localName: 'tokens.txt',
        url: '$baseUrl/tokens.txt',
        sizeBytes: 48697,
        sha256:
            '8b294db9045d6e5f94647f4c1eec1af4da143a75053c399611444b378ff966ac',
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
