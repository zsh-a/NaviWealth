import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  test('mobile web uses touch density below the compact breakpoint', () {
    expect(
      useCompactDensity(
        TargetPlatform.android,
        true,
        windowWidth: Breakpoints.mobile - 1,
      ),
      isFalse,
    );
  });

  test('wide web uses pointer-oriented density', () {
    expect(
      useCompactDensity(
        TargetPlatform.android,
        true,
        windowWidth: Breakpoints.mobile,
      ),
      isTrue,
    );
  });

  test('native density follows the input platform', () {
    expect(useCompactDensity(TargetPlatform.iOS, false), isFalse);
    expect(useCompactDensity(TargetPlatform.macOS, false), isTrue);
  });
}
