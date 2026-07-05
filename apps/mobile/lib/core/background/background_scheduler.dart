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

/// Stable workmanager task name for the daily Morning Briefing.
/// Mirrors the `Info.plist::BGTaskSchedulerPermittedIdentifiers`
/// entry and the iOS `AppDelegate.swift` registration call site —
/// **never** rename one without updating both.
const String kMorningBriefingTaskName = 'com.naviwealth.morningBriefing';

/// Stable workmanager task name for KnowledgeOS routine reminders.
/// The background isolate only stamps a due flag; foreground catch-up runs
/// `knowledge_routine_due` through the shared agent controller.
const String kKnowledgeRoutineDueTaskName =
    'com.naviwealth.knowledgeRoutineDue';

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

/// SharedPreferences key set by the background callback when the OS
/// fires the periodic task. The foreground app reads it on launch and
/// triggers an in-process scheduled-agent tick if found (the background
/// isolate can't run the full agent — no ProviderContainer / Drift access).
const String kMorningBriefingDueAtKey = 'lifeos.health.briefing.dueAt';

/// SharedPreferences key set by the background callback when KnowledgeOS
/// routine reminders should catch up in the foreground process.
const String kKnowledgeRoutineDueAtKey = 'lifeos.knowledge.routineDue.dueAt';

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

const BackgroundTaskSpec kMorningBriefingBackgroundTask = BackgroundTaskSpec(
  name: kMorningBriefingTaskName,
  dueAtPreferenceKey: kMorningBriefingDueAtKey,
  defaultInterval: Duration(hours: 24),
);

const BackgroundTaskSpec kKnowledgeRoutineDueBackgroundTask =
    BackgroundTaskSpec(
      name: kKnowledgeRoutineDueTaskName,
      dueAtPreferenceKey: kKnowledgeRoutineDueAtKey,
      defaultInterval: Duration(hours: 24),
    );

const BackgroundTaskSpec kExecutionReviewBackgroundTask = BackgroundTaskSpec(
  name: kExecutionReviewTaskName,
  dueAtPreferenceKey: kExecutionReviewDueAtKey,
  defaultInterval: Duration(days: 7),
);

const NotificationChannelSpec kMorningBriefingWakeNotificationChannel =
    NotificationChannelSpec(
      id: 'lifeos.health.briefing',
      name: 'Morning Briefing',
      description: 'Daily HealthOS morning briefing summaries.',
    );

int morningBriefingWakeNotificationId(DateTime localDay) =>
    localDay.year * 10000 + localDay.month * 100 + localDay.day;

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

const List<BackgroundTaskSpec> kBackgroundTaskSpecs = <BackgroundTaskSpec>[
  kMorningBriefingBackgroundTask,
  kKnowledgeRoutineDueBackgroundTask,
  kExecutionReviewBackgroundTask,
  kGarminSyncBackgroundTask,
  kHealthPlatformSyncBackgroundTask,
];

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
