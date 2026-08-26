/// Cross-platform background-task scheduler for autonomous agents
/// (`docs/architecture/lifeos-shell.md` §7.3, D-2.5b).
///
/// Narrow surface: register / cancel named background task specs. Domain
/// providers own which specs should be active; the actual platform driver
/// (Android WorkManager, iOS BGTaskScheduler) sits in
/// [createBackgroundScheduler]'s io impl and goes through `package:workmanager`.
///
/// **iOS caveats** (BGTaskScheduler reality, not a code bug):
///   * minimum effective frequency ≈ 15 min;
///   * not guaranteed to fire at the requested time — OS picks an
///     opportunistic moment in the window;
///   * the app must register the task identifier in `Info.plist`
///     under `BGTaskSchedulerPermittedIdentifiers` (already done).
///
/// **Web / desktop** get a no-op stub via conditional import.
library;

import '../notifications/notification_service.dart';

/// Background-safe inspection of a precomputed Life attention snapshot.
const String kLifeAttentionTaskName = 'com.naviwealth.lifeAttention';

/// Stable workmanager task name for ExecutionOS weekly review catch-up.
/// Foreground catch-up runs `execution_review` through the shared agent
/// controller after this task stamps its due flag.
const String kExecutionReviewTaskName = 'com.naviwealth.executionReview';

/// Stable workmanager task name for best-effort Garmin background sync.
/// Mirrors iOS native task registration and Info.plist identifiers.
const String kGarminSyncTaskName = 'com.naviwealth.garminSync';

/// Stable workmanager task name for best-effort HealthKit / Health Connect
/// platform sync. Mirrors iOS native task registration and Info.plist
/// identifiers.
const String kHealthPlatformSyncTaskName = 'com.naviwealth.healthPlatformSync';

/// Stable workmanager task name for the Android GitHub self-update check.
/// The task only reads the public release manifest and posts a local
/// notification; APK installation remains an explicit foreground action.
const String kNativeUpdateTaskName = 'com.naviwealth.nativeUpdate';

const String kLifeAttentionDueAtKey = 'lifeos.attention.dueAt';

/// SharedPreferences key set by the background callback when ExecutionOS
/// review should catch up in the foreground process.
const String kExecutionReviewDueAtKey = 'lifeos.execution.review.dueAt';

/// SharedPreferences key set by the background callback when Garmin data
/// should be refreshed in-process on next foreground launch/resume.
const String kGarminSyncDueAtKey = 'lifeos.health.garminSync.dueAt';

/// SharedPreferences key set by the background callback when native
/// HealthKit / Health Connect data should be refreshed in-process on next
/// foreground launch/resume.
const String kHealthPlatformSyncDueAtKey = 'lifeos.health.platformSync.dueAt';

/// SharedPreferences key stamped when the Android update task wakes.
const String kNativeUpdateDueAtKey =
    'naviwealth.update.native.background.dueAt';

class BackgroundTaskSpec {
  const BackgroundTaskSpec({
    required this.name,
    required this.dueAtPreferenceKey,
    required this.defaultInterval,
  });

  /// Stable workmanager task identifier.
  final String name;

  /// SharedPreferences key stamped by the background isolate when this task
  /// wakes. The foreground app owns the real work.
  final String dueAtPreferenceKey;

  /// Requested cadence when callers do not provide a narrower interval.
  final Duration defaultInterval;
}

const BackgroundTaskSpec kLifeAttentionBackgroundTask = BackgroundTaskSpec(
  name: kLifeAttentionTaskName,
  dueAtPreferenceKey: kLifeAttentionDueAtKey,
  defaultInterval: Duration(hours: 24),
);

const BackgroundTaskSpec kExecutionReviewBackgroundTask = BackgroundTaskSpec(
  name: kExecutionReviewTaskName,
  dueAtPreferenceKey: kExecutionReviewDueAtKey,
  defaultInterval: Duration(days: 7),
);

const BackgroundTaskSpec kGarminSyncBackgroundTask = BackgroundTaskSpec(
  name: kGarminSyncTaskName,
  dueAtPreferenceKey: kGarminSyncDueAtKey,
  defaultInterval: Duration(hours: 6),
);

const BackgroundTaskSpec kHealthPlatformSyncBackgroundTask = BackgroundTaskSpec(
  name: kHealthPlatformSyncTaskName,
  dueAtPreferenceKey: kHealthPlatformSyncDueAtKey,
  defaultInterval: Duration(hours: 6),
);

const BackgroundTaskSpec kNativeUpdateBackgroundTask = BackgroundTaskSpec(
  name: kNativeUpdateTaskName,
  dueAtPreferenceKey: kNativeUpdateDueAtKey,
  defaultInterval: Duration(hours: 12),
);

const List<BackgroundTaskSpec> kBackgroundTaskSpecs = <BackgroundTaskSpec>[
  kLifeAttentionBackgroundTask,
  kExecutionReviewBackgroundTask,
  kGarminSyncBackgroundTask,
  kHealthPlatformSyncBackgroundTask,
  kNativeUpdateBackgroundTask,
];

const NotificationChannelSpec kLifeAttentionNotificationChannel =
    NotificationChannelSpec(
      id: 'lifeos.attention',
      name: 'Life Navigator',
      description: 'High-priority evidence-backed LifeOS judgments.',
    );

int lifeAttentionNotificationId(DateTime localDay) =>
    100000000 + localDay.year * 10000 + localDay.month * 100 + localDay.day;

BackgroundTaskSpec? backgroundTaskSpecForName(String taskName) {
  for (final spec in kBackgroundTaskSpecs) {
    if (spec.name == taskName) return spec;
  }
  return null;
}

abstract class BackgroundScheduler {
  /// `true` when the platform supports background tasks at all.
  /// `false` on web (no service worker for this) / desktop.
  Future<bool> isAvailable();

  /// Idempotent. Sets up the workmanager dispatcher; safe to call
  /// from every cold start. No-op on web / desktop.
  Future<void> initialize();

  /// Schedule [task]. Uses [interval] when supplied, otherwise
  /// [BackgroundTaskSpec.defaultInterval]. Replacing a previous schedule is
  /// safe because the underlying workmanager API dedupes by [task.name].
  Future<void> registerTask(BackgroundTaskSpec task, {Duration? interval});

  /// Cancel the previously-registered [task].
  Future<void> cancelTask(BackgroundTaskSpec task);
}
