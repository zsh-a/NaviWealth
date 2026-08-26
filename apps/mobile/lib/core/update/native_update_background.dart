/// Android background scheduling for the GitHub self-update check.
///
/// The foreground app owns registration so the task follows the app-level
/// notification preference and release configuration. The work itself is
/// deliberately kept in [lifeosBackgroundCallback], where WorkManager can
/// wake a fresh isolate even when the app UI is not running.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background/background_scheduler.dart';
import '../background/providers.dart';
import '../config/app_config.dart';
import '../config/providers.dart';
import '../logging/app_logger.dart';
import '../logging/providers.dart';
import '../notifications/notification_preferences.dart';
import 'native_update.dart';

/// Mounts the Android update reminder task after the first frame.
///
/// This provider is intentionally not auth-gated: release notifications must
/// work for local-only users and before a user has signed in. It is also
/// separate from the domain bootstrap because software updates are app-level
/// infrastructure rather than a LifeOS domain.
final nativeUpdateBackgroundBootstrapProvider = Provider<void>((ref) {
  final config = ref.watch(appConfigProvider);
  final enabled = ref.watch(notificationsEnabledProvider);
  final scheduler = ref.watch(backgroundSchedulerProvider);
  final logger = ref.watch(loggerProvider);

  unawaited(
    _reconcileNativeUpdateTask(
      config: config,
      notificationsEnabled: enabled,
      scheduler: scheduler,
      logger: logger,
    ),
  );
});

Future<void> _reconcileNativeUpdateTask({
  required AppConfig config,
  required bool notificationsEnabled,
  required BackgroundScheduler scheduler,
  required AppLogger logger,
}) async {
  try {
    final shouldSchedule =
        isAndroidNativePlatform &&
        config.hasNativeUpdateTarget &&
        notificationsEnabled;
    if (!shouldSchedule) {
      await scheduler.cancelTask(kNativeUpdateBackgroundTask);
      return;
    }
    if (!await scheduler.isAvailable()) return;

    await scheduler.registerTask(kNativeUpdateBackgroundTask);
    logger.i(
      'Native update background check scheduled '
      '(interval=${kNativeUpdateBackgroundTask.defaultInterval.inHours}h)',
    );
  } on Object catch (error, stackTrace) {
    logger.w(
      'Native update background scheduling failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
