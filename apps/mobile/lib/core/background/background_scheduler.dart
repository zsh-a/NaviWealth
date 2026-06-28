/// Cross-platform background-task scheduler for autonomous agents
/// (`docs/architecture/lifeos-shell.md` §7.3, D-2.5b).
///
/// Narrow surface: register / cancel HealthOS background tasks. The actual
/// platform driver (Android WorkManager, iOS BGTaskScheduler) sits in
/// [createBackgroundScheduler]'s io impl and goes through
/// `package:workmanager`.
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

/// Stable workmanager task name for the daily Morning Briefing.
/// Mirrors the `Info.plist::BGTaskSchedulerPermittedIdentifiers`
/// entry and the iOS `AppDelegate.swift` registration call site —
/// **never** rename one without updating both.
const String kMorningBriefingTaskName = 'com.naviwealth.morningBriefing';

/// Stable workmanager task name for best-effort Garmin background sync.
/// Mirrors iOS native task registration and Info.plist identifiers.
const String kGarminSyncTaskName = 'com.naviwealth.garminSync';

/// Stable workmanager task name for best-effort HealthKit / Health Connect
/// platform sync. Mirrors iOS native task registration and Info.plist
/// identifiers.
const String kHealthPlatformSyncTaskName = 'com.naviwealth.healthPlatformSync';

/// SharedPreferences key set by the background callback when the OS
/// fires the periodic task. The foreground app reads it on launch and
/// triggers an in-process agent run if found (the background isolate
/// can't run the full agent — no ProviderContainer / Drift access).
const String kMorningBriefingDueAtKey = 'lifeos.health.briefing.dueAt';

/// SharedPreferences key set by the background callback when Garmin data
/// should be refreshed in-process on next foreground launch/resume.
const String kGarminSyncDueAtKey = 'lifeos.health.garminSync.dueAt';

/// SharedPreferences key set by the background callback when native
/// HealthKit / Health Connect data should be refreshed in-process on next
/// foreground launch/resume.
const String kHealthPlatformSyncDueAtKey = 'lifeos.health.platformSync.dueAt';

abstract class BackgroundScheduler {
  /// `true` when the platform supports background tasks at all.
  /// `false` on web (no service worker for this) / desktop.
  Future<bool> isAvailable();

  /// Idempotent. Sets up the workmanager dispatcher; safe to call
  /// from every cold start. No-op on web / desktop.
  Future<void> initialize();

  /// Schedule the Morning Briefing wake-up. Uses [interval] as the
  /// requested cadence (default 24h, but iOS may collapse to the
  /// minimum allowed). Replacing a previous schedule is safe — the
  /// underlying workmanager API uses the unique name to dedupe.
  Future<void> registerMorningBriefing({
    Duration interval = const Duration(hours: 24),
  });

  /// Schedule best-effort Garmin data sync. The callback only stamps a due
  /// flag; the foreground app runs the real Rust/secure-storage sync.
  Future<void> registerGarminSync({
    Duration interval = const Duration(hours: 6),
  });

  /// Schedule best-effort HealthKit / Health Connect sync. The callback only
  /// stamps a due flag; the foreground app runs the real Drift-backed sync.
  Future<void> registerHealthPlatformSync({
    Duration interval = const Duration(hours: 6),
  });

  /// Cancel the previously-registered Morning Briefing task. Called
  /// when the user toggles HealthOS off so we don't keep waking the
  /// device for a domain they've disabled.
  Future<void> cancelMorningBriefing();

  /// Cancel the previously-registered Garmin sync task.
  Future<void> cancelGarminSync();

  /// Cancel the previously-registered HealthKit / Health Connect sync task.
  Future<void> cancelHealthPlatformSync();
}
