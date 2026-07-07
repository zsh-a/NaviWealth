import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_foreground_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start triggers an immediate catch-up tick', () async {
    final calls = <DateTime>[];
    final localNow = DateTime(2026, 5, 27, 9);
    final scheduler = AgentForegroundScheduler(
      tick: (now) async {
        calls.add(now);
        return 1;
      },
      clock: () => localNow,
    );
    addTearDown(scheduler.stop);

    scheduler.start();
    await pumpEventQueue();

    expect(calls, [localNow.toUtc()]);
  });

  test('resumed app state triggers a foreground catch-up tick', () async {
    final calls = <DateTime>[];
    final localNow = DateTime(2026, 5, 27, 9);
    final scheduler = AgentForegroundScheduler(
      tick: (now) async {
        calls.add(now);
        return 1;
      },
      clock: () => localNow,
    );
    addTearDown(scheduler.stop);

    scheduler.start();
    await pumpEventQueue();
    calls.clear();

    scheduler.didChangeAppLifecycleState(AppLifecycleState.paused);
    scheduler.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();

    expect(calls, [localNow.toUtc()]);
  });

  test('concurrent triggers share one in-flight tick', () async {
    final completer = Completer<int>();
    var callCount = 0;
    final scheduler = AgentForegroundScheduler(
      tick: (_) {
        callCount += 1;
        return completer.future;
      },
    );

    final first = scheduler.triggerNow();
    final second = scheduler.triggerNow();
    await pumpEventQueue();

    expect(callCount, 1);
    completer.complete(0);
    await Future.wait([first, second]);
  });
}
