import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/bootstrap/post_frame_startup.dart';

void main() {
  testWidgets('post-frame startup does not run before first paint', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var started = false;

    schedulePostFrameStartup(
      container,
      runner: () async {
        started = true;
      },
    );

    expect(started, isFalse);

    await tester.pumpWidget(const SizedBox());

    expect(started, isTrue);
  });
}
