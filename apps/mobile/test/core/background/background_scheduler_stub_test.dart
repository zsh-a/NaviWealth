import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/background/background_scheduler.dart';
import 'package:naviwealth/core/background/background_scheduler_stub.dart';

void main() {
  test('morning briefing task identifiers stay stable', () {
    expect(kMorningBriefingTaskName, 'com.naviwealth.morningBriefing');
    expect(kMorningBriefingDueAtKey, 'lifeos.health.briefing.dueAt');
  });

  test('native iOS task registration mirrors Dart task identifiers', () {
    final appRoot = _appRoot();
    final infoPlist = File(
      '${appRoot.path}/ios/Runner/Info.plist',
    ).readAsStringSync();
    final appDelegate = File(
      '${appRoot.path}/ios/Runner/AppDelegate.swift',
    ).readAsStringSync();
    final callback = File(
      '${appRoot.path}/lib/core/background/background_callback.dart',
    ).readAsStringSync();

    expect(infoPlist, contains('BGTaskSchedulerPermittedIdentifiers'));
    expect(infoPlist, contains(kMorningBriefingTaskName));
    expect(appDelegate, contains(kMorningBriefingTaskName));
    expect(callback, contains("@pragma('vm:entry-point')"));
    expect(callback, contains('kMorningBriefingTaskName'));
    expect(callback, contains('kMorningBriefingDueAtKey'));
  });

  test('unsupported background scheduler is unavailable and no-ops', () async {
    final scheduler = createBackgroundScheduler();

    expect(await scheduler.isAvailable(), isFalse);
    await scheduler.initialize();
    await scheduler.registerMorningBriefing();
    await scheduler.registerMorningBriefing(
      interval: const Duration(minutes: 15),
    );
    await scheduler.cancelMorningBriefing();
  });
}

Directory _appRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File('${current.path}/pubspec.yaml').existsSync() &&
        Directory('${current.path}/lib').existsSync() &&
        Directory('${current.path}/ios').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate apps/mobile root');
    }
    current = parent;
  }
}
