import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/data/bcr_knowledge_foreground_sync.dart';

void main() {
  testWidgets('checks on startup/resume and polls only while foregrounded', (
    tester,
  ) async {
    var calls = 0;
    var cancellations = 0;
    final driver = BcrForegroundSync(
      refresh: () async {
        calls++;
      },
      cancel: () {
        cancellations++;
      },
    );
    driver.start();
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 29));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    driver.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 2);
    expect(cancellations, 1);
    driver.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 3);
    driver.stop();
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 3);
  });

  testWidgets('foreground opportunities coalesce while a check is pending', (
    tester,
  ) async {
    final gate = Completer<void>();
    var calls = 0;
    final driver = BcrForegroundSync(
      refresh: () {
        calls++;
        return gate.future;
      },
      cancel: () {},
    );
    driver.start();
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 1);
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    driver.stop();
  });
}
