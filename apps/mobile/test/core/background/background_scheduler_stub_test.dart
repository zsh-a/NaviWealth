import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/background/background_scheduler.dart';
import 'package:naviwealth/core/background/background_scheduler_stub.dart';

void main() {
  test('morning briefing task identifiers stay stable', () {
    expect(kMorningBriefingTaskName, 'com.naviwealth.morningBriefing');
    expect(kMorningBriefingDueAtKey, 'lifeos.health.briefing.dueAt');
    expect(kMorningBriefingBackgroundTask.name, kMorningBriefingTaskName);
    expect(
      kMorningBriefingBackgroundTask.dueAtPreferenceKey,
      kMorningBriefingDueAtKey,
    );
    expect(
      kMorningBriefingBackgroundTask.defaultInterval,
      const Duration(hours: 24),
    );
    expect(kGarminSyncTaskName, 'com.naviwealth.garminSync');
    expect(kGarminSyncDueAtKey, 'lifeos.health.garminSync.dueAt');
    expect(kGarminSyncBackgroundTask.name, kGarminSyncTaskName);
    expect(kGarminSyncBackgroundTask.dueAtPreferenceKey, kGarminSyncDueAtKey);
    expect(kGarminSyncBackgroundTask.defaultInterval, const Duration(hours: 6));
    expect(kHealthPlatformSyncTaskName, 'com.naviwealth.healthPlatformSync');
    expect(kHealthPlatformSyncDueAtKey, 'lifeos.health.platformSync.dueAt');
    expect(kHealthPlatformSyncBackgroundTask.name, kHealthPlatformSyncTaskName);
    expect(
      kHealthPlatformSyncBackgroundTask.dueAtPreferenceKey,
      kHealthPlatformSyncDueAtKey,
    );
    expect(
      kHealthPlatformSyncBackgroundTask.defaultInterval,
      const Duration(hours: 6),
    );
    expect(kBackgroundTaskSpecs.map((spec) => spec.name), <String>[
      kMorningBriefingTaskName,
      kGarminSyncTaskName,
      kHealthPlatformSyncTaskName,
    ]);
    expect(
      backgroundTaskSpecForName(kGarminSyncTaskName),
      kGarminSyncBackgroundTask,
    );
    expect(backgroundTaskSpecForName('unknown'), isNull);
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
    expect(infoPlist, contains(kGarminSyncTaskName));
    expect(infoPlist, contains(kHealthPlatformSyncTaskName));
    expect(appDelegate, contains(kMorningBriefingTaskName));
    expect(appDelegate, contains(kGarminSyncTaskName));
    expect(appDelegate, contains(kHealthPlatformSyncTaskName));
    expect(callback, contains("@pragma('vm:entry-point')"));
    expect(callback, contains('backgroundTaskSpecForName'));
    expect(callback, contains('kMorningBriefingTaskName'));
    expect(callback, contains('dueAtPreferenceKey'));
  });

  test('unsupported background scheduler is unavailable and no-ops', () async {
    final scheduler = createBackgroundScheduler();

    expect(await scheduler.isAvailable(), isFalse);
    await scheduler.initialize();
    await scheduler.registerTask(kMorningBriefingBackgroundTask);
    await scheduler.registerTask(
      kMorningBriefingBackgroundTask,
      interval: const Duration(minutes: 15),
    );
    await scheduler.registerTask(kGarminSyncBackgroundTask);
    await scheduler.registerTask(
      kGarminSyncBackgroundTask,
      interval: const Duration(minutes: 15),
    );
    await scheduler.registerTask(kHealthPlatformSyncBackgroundTask);
    await scheduler.registerTask(
      kHealthPlatformSyncBackgroundTask,
      interval: const Duration(minutes: 15),
    );
    await scheduler.cancelTask(kMorningBriefingBackgroundTask);
    await scheduler.cancelTask(kGarminSyncBackgroundTask);
    await scheduler.cancelTask(kHealthPlatformSyncBackgroundTask);
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
