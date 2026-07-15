import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart' show autoUpdateGoldenFiles;
import 'package:golden_toolkit/golden_toolkit.dart';

/// README screenshots share Linux as their canonical rasterizer. Other hosts
/// still pump every production surface, and `--update-goldens` remains useful
/// for local previews.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  return GoldenToolkit.runWithConfiguration(
    testMain,
    config: GoldenToolkitConfiguration(
      skipGoldenAssertion: () => !Platform.isLinux && !autoUpdateGoldenFiles,
      enableRealShadows: true,
    ),
  );
}
