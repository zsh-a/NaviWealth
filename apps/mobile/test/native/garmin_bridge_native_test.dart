import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_bridge.dart';

void main() {
  const relativeLibraryPath =
      'native/lifeos_native/target/release/liblifeos_native.dylib';
  final library = File(relativeLibraryPath);
  final skipReason = library.existsSync()
      ? null
      : 'liblifeos_native.dylib not found; run cargo build --release in '
            'apps/mobile/native/lifeos_native';

  test(
    'cold-start Garmin bridge initializes the real native runtime',
    () async {
      final bridge = GarminBridge(libraryPath: library.absolute.path);

      final state = await bridge.init(isCn: true);

      expect(state.type, GarminAuthStateType.unauthenticated);
    },
    skip: skipReason,
  );
}
