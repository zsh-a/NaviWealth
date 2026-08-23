import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/background/background_scheduler.dart';
import 'package:naviwealth/core/background/background_scheduler_stub.dart';

void main() {
  test('Life attention task identifiers stay stable', () {
    expect(kLifeAttentionTaskName, 'com.naviwealth.lifeAttention');
    expect(kLifeAttentionDueAtKey, 'lifeos.attention.dueAt');
    expect(kLifeAttentionBackgroundTask.name, kLifeAttentionTaskName);
    expect(
      kLifeAttentionBackgroundTask.dueAtPreferenceKey,
      kLifeAttentionDueAtKey,
    );
    expect(
      kLifeAttentionBackgroundTask.defaultInterval,
      const Duration(hours: 24),
    );
    expect(kExecutionReviewTaskName, 'com.naviwealth.executionReview');
    expect(kExecutionReviewDueAtKey, 'lifeos.execution.review.dueAt');
    expect(kExecutionReviewBackgroundTask.name, kExecutionReviewTaskName);
    expect(
      kExecutionReviewBackgroundTask.dueAtPreferenceKey,
      kExecutionReviewDueAtKey,
    );
    expect(
      kExecutionReviewBackgroundTask.defaultInterval,
      const Duration(days: 7),
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
      kLifeAttentionTaskName,
      kExecutionReviewTaskName,
      kGarminSyncTaskName,
      kHealthPlatformSyncTaskName,
    ]);
    expect(
      backgroundTaskSpecForName(kExecutionReviewTaskName),
      kExecutionReviewBackgroundTask,
    );
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
    expect(infoPlist, contains(kLifeAttentionTaskName));
    expect(infoPlist, contains(kExecutionReviewTaskName));
    expect(infoPlist, contains(kGarminSyncTaskName));
    expect(infoPlist, contains(kHealthPlatformSyncTaskName));
    expect(appDelegate, contains(kLifeAttentionTaskName));
    expect(appDelegate, contains(kExecutionReviewTaskName));
    expect(appDelegate, contains(kGarminSyncTaskName));
    expect(appDelegate, contains(kHealthPlatformSyncTaskName));
    expect(callback, contains("@pragma('vm:entry-point')"));
    expect(callback, contains('backgroundTaskSpecForName'));
    expect(callback, contains('kLifeAttentionTaskName'));
    expect(callback, contains('dueAtPreferenceKey'));
  });

  test('unsupported background scheduler is unavailable and no-ops', () async {
    final scheduler = createBackgroundScheduler();

    expect(await scheduler.isAvailable(), isFalse);
    await scheduler.initialize();
    await scheduler.registerTask(kLifeAttentionBackgroundTask);
    await scheduler.registerTask(
      kLifeAttentionBackgroundTask,
      interval: const Duration(minutes: 15),
    );
    await scheduler.registerTask(kExecutionReviewBackgroundTask);
    await scheduler.registerTask(
      kExecutionReviewBackgroundTask,
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
    await scheduler.cancelTask(kLifeAttentionBackgroundTask);
    await scheduler.cancelTask(kExecutionReviewBackgroundTask);
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
