/// Cross-platform local-notification surface for autonomous agents
/// (`docs/architecture/lifeos-shell.md` §7.3, D-2.5b).
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
  ///
  /// [channel] picks which OS notification channel to post on. Defaults
  /// to HealthOS's Morning Briefing channel for back-compat with the
  /// original call sites; KnowledgeOS agents pass
  /// [NotificationChannelSpec.knowledgeReview] so the user can mute
  /// channels independently from the system settings.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
    NotificationChannelSpec channel = NotificationChannelSpec.healthBriefing,
  });

  /// Cancel a previously-posted notification by [id]. Used by tests
  /// and by Settings (e.g. "stop reminding me").
  Future<void> cancel(int id);
}

/// Identifies which Android notification channel a message lands on
/// (iOS ignores channels but still routes everything through the same
/// surface). Adding a new channel is one entry here plus a one-liner
/// in the IO impl so the platform creates it up front.
enum NotificationChannelSpec {
  /// HealthOS Morning Briefing channel — daily briefing summaries.
  healthBriefing(
    id: 'lifeos.health.briefing',
    name: 'Morning Briefing',
    description: 'Daily HealthOS morning briefing summaries.',
  ),

  /// KnowledgeOS review channel — due decisions, stale assumptions,
  /// recurring routines. One channel covers all Knowledge agents so
  /// the user has a single mute switch.
  knowledgeReview(
    id: 'lifeos.knowledge.review',
    name: 'Knowledge Review',
    description:
        'KnowledgeOS reminders: due decisions, stale assumptions, and recurring routines.',
  );

  const NotificationChannelSpec({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
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

  /// Recovery alert notification id — offset above briefing range
  /// so the two never collide.
  static int idForRecoveryAlert(DateTime localDay) =>
      0x8000000 + localDay.year * 10000 + localDay.month * 100 + localDay.day;
}

/// Stable ID space used by KnowledgeOS notifications. Channel metadata
/// lives on [NotificationChannelSpec.knowledgeReview]; this class only
/// owns the per-notification id derivation so the workmanager dispatcher
/// (`background_callback.dart`) can construct the same values without
/// importing the agent module.
class KnowledgeNotifications {
  KnowledgeNotifications._();

  /// Stable per-day id derived from the local date, offset above the
  /// HealthOS range so the two never collide in the OS notification
  /// list. Reuse on the same day replaces, not stacks.
  static int idForRoutineDigest(DateTime localDay) =>
      0x10000000 + localDay.year * 10000 + localDay.month * 100 + localDay.day;
}
