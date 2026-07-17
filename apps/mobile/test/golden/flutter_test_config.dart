import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Test config scoped to `test/golden/`.
///
/// Two things matter here:
///
/// Platform comparison policy, font loading, and real-shadow cleanup live in
/// `_golden_setup.dart`, beside the native matcher that enforces them.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await testMain();
}
