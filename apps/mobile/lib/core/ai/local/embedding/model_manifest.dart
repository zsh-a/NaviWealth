/// Manifest of model assets the embedder needs at runtime
/// (D-1.7c per `docs/lifeos-shell.md` §6.6).
///
/// Each [ModelBundle] is a logical group of files that get
/// downloaded together (e.g. the EmbeddingGemma weights + tokenizer
/// JSON, or the platform's `libonnxruntime` binary). The Settings
/// UI iterates registered bundles; the bootstrap auto-discovery
/// checks each bundle for completeness before electing to use the
/// Rust embedder over the stub.
///
/// **Cross-domain neutral**: lives in `embedding/` because that's
/// the only consumer today, but the types don't carry finance- or
/// embedder-specific fields. A future HealthOS / TimeOS asset (e.g.
/// a speech recogniser model) can reuse the same types.
library;

import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

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
// Concrete bundles
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

/// ONNX Runtime native lib for the current platform. We use
/// `ort-load-dynamic` (see `Cargo.toml`) so this file is the
/// dynamic library ORT discovers via `ORT_DYLIB_PATH`.
///
/// Returns `null` on platforms we don't have a binary for (the
/// embedder loader will then surface a friendly "unsupported
/// platform" message instead of crashing).
ModelBundle? onnxRuntimeBundle() {
  const ortVersion = '1.20.1';
  const base =
      'https://github.com/microsoft/onnxruntime/releases/download/v$ortVersion';

  String? archiveUrl;
  String? archiveSubpath;
  String? localName;
  int? sizeBytes;

  // Use the ABI to pick the right artefact. Microsoft ships
  // platform-specific archives that we'd normally extract; for an
  // in-app downloader we point the URL at the archive and the
  // installer decompresses to the bundle dir.
  switch (Abi.current()) {
    case Abi.macosArm64:
      archiveUrl = '$base/onnxruntime-osx-arm64-$ortVersion.tgz';
      archiveSubpath =
          'onnxruntime-osx-arm64-$ortVersion/lib/libonnxruntime.$ortVersion.dylib';
      localName = 'libonnxruntime.dylib';
      sizeBytes = 16 * 1024 * 1024;
      break;
    case Abi.macosX64:
      archiveUrl = '$base/onnxruntime-osx-x86_64-$ortVersion.tgz';
      archiveSubpath =
          'onnxruntime-osx-x86_64-$ortVersion/lib/libonnxruntime.$ortVersion.dylib';
      localName = 'libonnxruntime.dylib';
      sizeBytes = 18 * 1024 * 1024;
      break;
    case Abi.linuxX64:
      archiveUrl = '$base/onnxruntime-linux-x64-$ortVersion.tgz';
      archiveSubpath =
          'onnxruntime-linux-x64-$ortVersion/lib/libonnxruntime.so.$ortVersion';
      localName = 'libonnxruntime.so';
      sizeBytes = 20 * 1024 * 1024;
      break;
    case Abi.androidArm64:
      // Android: Microsoft ships an AAR with the .so inside. Skip
      // for now; revisit when the app actually targets Android.
      return null;
    default:
      return null;
  }

  // For MVP the downloader supports plain HTTPS downloads only. The
  // .tgz archive workflow needs a decompress step we haven't built;
  // until then, ORT install on macOS expects the user to drop a
  // pre-extracted `libonnxruntime.dylib` into the install dir.
  // We still surface the bundle to the UI as a manual install,
  // pointing the user at the README's curl recipe.
  // (Setting the URL to the archive page so the user knows where to look.)
  return ModelBundle(
    id: 'onnxruntime-${Platform.operatingSystem}',
    displayName: 'ONNX Runtime $ortVersion',
    description:
        '推理引擎(`ort-load-dynamic`)。手动下载 + 解压一个文件;'
        '详见 README。Archive: $archiveUrl,需提取 $archiveSubpath → $localName。',
    files: [
      ModelFile(
        localName: localName,
        url: archiveUrl,
        sizeBytes: sizeBytes,
      ),
    ],
  );
}
