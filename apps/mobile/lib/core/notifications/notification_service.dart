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
  /// `false` on web / desktop.
  Future<bool> isAvailable();

  /// Whether the OS has granted notification permission. iOS / Android
  /// 13+ require an explicit prompt; older Androids return `true`.
  Future<bool> hasPermissions();

  /// Show the OS permission sheet. Returns `true` if granted.
  Future<bool> requestPermissions();

  /// One-shot notification. Reuse [id] to replace an existing one (the
  /// caller supplies a stable [id], repeated notifications replace the
  /// previous entry instead of stacking.
  ///
  /// [channel] picks which OS notification channel to post on. Channels are
  /// domain-owned constants; core only knows their transport shape.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required NotificationChannelSpec channel,
    String? payload,
  });

  /// Cancel a previously-posted notification by [id]. Used by tests
  /// and by Settings (e.g. "stop reminding me").
  Future<void> cancel(int id);
}

/// Identifies which Android notification channel a message lands on
/// (iOS ignores channels but still routes everything through the same
/// surface).
class NotificationChannelSpec {
  const NotificationChannelSpec({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}
