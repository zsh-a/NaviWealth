import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Package-wide widget test setup.
///
/// Golden tests under `test/golden/` keep their own config so PNG comparison
/// policy and GoldenToolkit defaults stay scoped to visual baselines.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await testMain();
}
