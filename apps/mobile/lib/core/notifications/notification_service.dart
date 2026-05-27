/// Cross-platform local-notification surface for autonomous agents
/// (`docs/lifeos-shell.md` §7.3, D-2.5b).
///
/// Narrow on purpose: agents fire a one-shot notification when their
/// run finishes. No scheduling here — [BackgroundScheduler] handles
/// the cron side; the agent decides whether to notify after its run.
///
/// Web and desktop get a not-supported stub via conditional import so
/// the rest of the app doesn't have to know the platform matrix.
library;

abstract class NotificationService {
  /// `true` when the platform supports local notifications at all.
  /// `false` on web / desktop (HealthOS isn't shipped there anyway,
  /// per northstar §1.1).
  Future<bool> isAvailable();

  /// Whether the OS has granted notification permission. iOS / Android
  /// 13+ require an explicit prompt; older Androids return `true`.
  Future<bool> hasPermissions();

  /// Show the OS permission sheet. Returns `true` if granted.
  Future<bool> requestPermissions();

  /// One-shot notification. Reuse [id] to replace an existing one (the
  /// Morning Briefing uses a stable id per day so the morning toast
  /// gets replaced, not stacked).
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  /// Cancel a previously-posted notification by [id]. Used by tests
  /// and by Settings (e.g. "stop reminding me").
  Future<void> cancel(int id);
}

/// Stable channel + ID space used by HealthOS notifications. Keep
/// these in one place so the workmanager dispatcher in
/// `background_callback.dart` (top-level) can construct the same
/// values without importing the agent module.
class HealthNotifications {
  HealthNotifications._();

  static const String channelId = 'lifeos.health.briefing';
  static const String channelName = 'Morning Briefing';
  static const String channelDescription =
      'Daily HealthOS morning briefing summaries.';

  /// Stable per-day id derived from the local date (yyyymmdd as int),
  /// so a fresh run on the same day replaces the previous notification
  /// instead of stacking.
  static int idForBriefing(DateTime localDay) =>
      localDay.year * 10000 + localDay.month * 100 + localDay.day;
}
