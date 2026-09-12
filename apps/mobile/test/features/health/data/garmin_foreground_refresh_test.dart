import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_foreground_refresh.dart';

void main() {
  testWidgets(
    'start and resume refresh, background pauses checks and cancels work',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var refreshes = 0;
      var cancellations = 0;
      final driver = GarminForegroundRefresh(
        refresh: () async {
          refreshes++;
        },
        cancel: () async {
          cancellations++;
        },
      );
      addTearDown(driver.stop);
      driver.start();
      await tester.pump();
      expect(refreshes, 1);
      await tester.pump(const Duration(minutes: 5));
      expect(refreshes, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(hours: 2));
      await driver.check();
      expect(refreshes, 2);
      expect(cancellations, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(refreshes, 3);
      driver.stop();
      await tester.pump(const Duration(minutes: 10));
      expect(refreshes, 3);
    },
  );

  testWidgets(
    'foreground opportunities coalesce and inactive does not cancel MFA',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final gate = Completer<void>();
      var refreshes = 0;
      var cancellations = 0;
      final driver = GarminForegroundRefresh(
        refresh: () {
          refreshes++;
          return gate.future;
        },
        cancel: () async {
          cancellations++;
        },
      );
      addTearDown(driver.stop);
      driver.start();
      final second = driver.check();
      await tester.pump(const Duration(minutes: 10));
      expect(refreshes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(cancellations, 0);
      gate.complete();
      await second;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      driver.stop();
    },
  );

  testWidgets('starting while backgrounded does not fetch until resumed', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    var refreshes = 0;
    final driver = GarminForegroundRefresh(
      refresh: () async {
        refreshes++;
      },
      cancel: () async {},
    );
    addTearDown(driver.stop);
    driver.start();
    await tester.pump(const Duration(hours: 1));
    expect(refreshes, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(refreshes, 1);
    driver.stop();
  });
}
