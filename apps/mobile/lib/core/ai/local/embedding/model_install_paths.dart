/// Install-directory conventions for embedder model bundles
/// (D-1.7c per `docs/architecture/lifeos-shell.md` §6.6).
///
/// Bundles live under `<app_support>/ai-models/<bundle.id>/`. App
/// Support is the right home: it survives app updates, doesn't sync
/// to iCloud, and isn't visible in the iOS Files app (we don't want
/// users casually deleting model files).
///
/// Bootstrap auto-discovery consults this resolver to find the
/// active install paths without needing `--dart-define` overrides.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model_manifest.dart';

class ModelInstallPaths {
  ModelInstallPaths._(this.rootDir);

  /// Test/bootstrap seam — wrap an existing directory without going
  /// through `path_provider`. Used by [resolveEmbedderPaths] to read
  /// on-disk install state before any provider container exists.
  factory ModelInstallPaths.unsafeForDir(Directory rootDir) =>
      ModelInstallPaths._(rootDir);

  /// `<app_support>/ai-models/`. Bundles live in subdirs named after
  /// [ModelBundle.id].
  final Directory rootDir;

  Directory dirForBundle(ModelBundle bundle) =>
      Directory(p.join(rootDir.path, bundle.id));

  /// Absolute path to a [ModelFile] within [bundle]. Doesn't check
  /// existence — callers use [isComplete] for that.
  String filePath(ModelBundle bundle, ModelFile file) =>
      p.join(rootDir.path, bundle.id, file.localName);

  /// True iff every file in [bundle] exists on disk and its size
  /// (when known) matches the manifest. Quick check used at boot to
  /// decide stub vs. Rust embedder.
  ///
  /// Does **not** verify SHA-256 — that's the installer's job during
  /// download. A re-verify here would block bootstrap.
  Future<bool> isComplete(ModelBundle bundle) async {
    for (final file in bundle.files) {
      final f = File(filePath(bundle, file));
      if (!f.existsSync()) return false;
      final expected = file.sizeBytes;
      if (expected != null) {
        final actual = await f.length();
        // Allow ±5% wiggle since manifest sizes are approximate
        // (HuggingFace doesn't expose exact bytes pre-download).
        final delta = (actual - expected).abs();
        if (delta > expected * 0.05) return false;
      }
    }
    return true;
  }
}

/// Returns the shared model root and migrates the pre-ASR `embedders` folder
/// in place. [createIfMissing] is false for read-only bootstrap discovery.
Future<Directory> resolveModelInstallRoot(
  Directory supportDirectory, {
  bool createIfMissing = true,
}) async {
  final root = Directory(p.join(supportDirectory.path, 'ai-models'));
  final legacyRoot = Directory(p.join(supportDirectory.path, 'embedders'));
  if (!root.existsSync() && legacyRoot.existsSync()) {
    await legacyRoot.rename(root.path);
  }
  if (createIfMissing && !root.existsSync()) {
    await root.create(recursive: true);
  }
  return root;
}

/// Resolves the install root once at app start; cached for the
/// lifetime of the process. Tests can override with a temp dir.
final modelInstallPathsProvider = FutureProvider<ModelInstallPaths>((
  ref,
) async {
  final support = await getApplicationSupportDirectory();
  final root = await resolveModelInstallRoot(support);
  return ModelInstallPaths._(root);
});
