/// Native (iOS / Android) [BackgroundScheduler] backed by
/// `package:workmanager`.
library;

import 'dart:io';

import 'package:workmanager/workmanager.dart';

import 'background_callback.dart';
import 'background_scheduler.dart';

BackgroundScheduler createBackgroundScheduler() => _WorkmanagerScheduler();

class _WorkmanagerScheduler implements BackgroundScheduler {
  _WorkmanagerScheduler();

  bool _initialized = false;

  @override
  Future<bool> isAvailable() async => Platform.isIOS || Platform.isAndroid;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (!await isAvailable()) return;
    await Workmanager().initialize(lifeosBackgroundCallback);
    _initialized = true;
  }

  @override
  Future<void> registerMorningBriefing({
    Duration interval = const Duration(hours: 24),
  }) async {
    if (!await isAvailable()) return;
    await initialize();
    if (Platform.isIOS) {
      // iOS only supports a single one-shot register via BGTaskScheduler.
      // workmanager exposes `registerOneOffTask` + recurring re-arm
      // inside the callback for true periodic-on-iOS, but for D-2.5b
      // we accept "fires opportunistically once per cycle" semantics.
      await Workmanager().registerOneOffTask(
        kMorningBriefingTaskName,
        kMorningBriefingTaskName,
        initialDelay: interval,
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      return;
    }
    // Android: native periodic task. 15 min minimum frequency at the
    // platform level — we clamp `interval` upward to satisfy that.
    final effective = interval < const Duration(minutes: 15)
        ? const Duration(minutes: 15)
        : interval;
    await Workmanager().registerPeriodicTask(
      kMorningBriefingTaskName,
      kMorningBriefingTaskName,
      frequency: effective,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  @override
  Future<void> cancelMorningBriefing() async {
    if (!await isAvailable()) return;
    await initialize();
    await Workmanager().cancelByUniqueName(kMorningBriefingTaskName);
  }
}
