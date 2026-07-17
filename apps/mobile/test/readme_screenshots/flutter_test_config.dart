import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// README screenshots share Linux as their canonical rasterizer. Other hosts
/// still pump every production surface, and `--update-goldens` remains useful
/// for local previews.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await testMain();
}
