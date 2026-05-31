/// Runtime path discovery for the native EmbeddingGemma embedder.
///
/// The in-app model installer owns user data (model files under App Support).
/// ONNX Runtime is a build-time native dependency, so bootstrap and Settings
/// both need the same answer to "is the Rust embedder usable next start?".
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../config/app_config.dart';
import '../../../config/providers.dart';
import 'model_install_paths.dart';
import 'model_manifest.dart';

enum EmbedderHostPlatform { android, macos, linux, other }

enum EmbedderModelPathSource { dartDefine, installedBundle, missing }

enum EmbedderOrtPathSource { dartDefine, bundled, missing }

class EmbedderPathResolution {
  const EmbedderPathResolution({
    required this.modelDir,
    required this.ortDylibPath,
    this.libraryPath,
    required this.modelSource,
    required this.ortSource,
  });

  final String modelDir;
  final String ortDylibPath;
  final String? libraryPath;
  final EmbedderModelPathSource modelSource;
  final EmbedderOrtPathSource ortSource;

  bool get isComplete => modelDir.isNotEmpty && ortDylibPath.isNotEmpty;

  List<String> get missingInputs => [
    if (modelDir.isEmpty) 'EmbeddingGemma model dir',
    if (ortDylibPath.isEmpty) 'ONNX Runtime dylib',
  ];
}

final embedderPathResolutionProvider = FutureProvider<EmbedderPathResolution>((
  ref,
) async {
  final config = ref.watch(appConfigProvider);
  return resolveEmbedderPaths(config);
});

Future<EmbedderPathResolution> resolveEmbedderPaths(
  AppConfig config, {
  Directory? supportDirectory,
  String? resolvedExecutable,
  EmbedderHostPlatform? hostPlatform,
  bool Function(String path)? fileExists,
}) async {
  var modelDir = config.rustEmbedderModelDir;
  var modelSource = modelDir.isEmpty
      ? EmbedderModelPathSource.missing
      : EmbedderModelPathSource.dartDefine;
  var ortDylibPath = config.rustEmbedderOrtDylibPath;
  var ortSource = ortDylibPath.isEmpty
      ? EmbedderOrtPathSource.missing
      : EmbedderOrtPathSource.dartDefine;

  if (modelDir.isEmpty) {
    try {
      final support =
          supportDirectory ?? await getApplicationSupportDirectory();
      final root = Directory(p.join(support.path, 'embedders'));
      final gemma = embeddingGemmaBundle();
      final gemmaDir = Directory(p.join(root.path, gemma.id));
      final paths = ModelInstallPaths.unsafeForDir(root);
      if (await paths.isComplete(gemma)) {
        modelDir = gemmaDir.path;
        modelSource = EmbedderModelPathSource.installedBundle;
      }
    } on Object {
      // path_provider failure or sandbox issue: report the missing model and
      // let bootstrap keep the stub embedder.
    }
  }

  if (ortDylibPath.isEmpty) {
    final discovered = discoverBundledOrtDylib(
      hostPlatform: hostPlatform,
      resolvedExecutable: resolvedExecutable,
      fileExists: fileExists,
    );
    if (discovered != null) {
      ortDylibPath = discovered;
      ortSource = EmbedderOrtPathSource.bundled;
    }
  }

  return EmbedderPathResolution(
    modelDir: modelDir,
    ortDylibPath: ortDylibPath,
    libraryPath: config.rustEmbedderLibraryPath.isEmpty
        ? null
        : config.rustEmbedderLibraryPath,
    modelSource: modelSource,
    ortSource: ortSource,
  );
}

String? discoverBundledOrtDylib({
  EmbedderHostPlatform? hostPlatform,
  String? resolvedExecutable,
  bool Function(String path)? fileExists,
}) {
  final platform = hostPlatform ?? currentEmbedderHostPlatform();
  final exists = fileExists ?? (path) => File(path).existsSync();
  if (platform == EmbedderHostPlatform.android) return 'libonnxruntime.so';
  if (platform != EmbedderHostPlatform.macos &&
      platform != EmbedderHostPlatform.linux) {
    return null;
  }

  final execDir = File(
    resolvedExecutable ?? Platform.resolvedExecutable,
  ).parent;
  final dylibName = platform == EmbedderHostPlatform.macos
      ? 'libonnxruntime.dylib'
      : 'libonnxruntime.so';

  final candidates = <String>[
    if (platform == EmbedderHostPlatform.macos)
      p.join(execDir.parent.path, 'Frameworks', dylibName),
    p.join(execDir.path, dylibName),
  ];
  for (final candidate in candidates) {
    final normalised = p.normalize(candidate);
    if (exists(normalised)) return normalised;
  }
  return null;
}

EmbedderHostPlatform currentEmbedderHostPlatform() {
  if (Platform.isAndroid) return EmbedderHostPlatform.android;
  if (Platform.isMacOS) return EmbedderHostPlatform.macos;
  if (Platform.isLinux) return EmbedderHostPlatform.linux;
  return EmbedderHostPlatform.other;
}
