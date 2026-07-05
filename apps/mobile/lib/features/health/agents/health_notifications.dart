import '../../../core/background/background_scheduler.dart';

const kHealthBriefingNotificationChannel =
    kMorningBriefingWakeNotificationChannel;

abstract final class HealthNotifications {
  /// Stable per-day id derived from the local date (yyyymmdd as int), so a
  /// fresh run on the same day replaces the previous notification.
  static int idForBriefing(DateTime localDay) =>
      morningBriefingWakeNotificationId(localDay);

  /// Recovery alert notification id, offset above the briefing range.
  static int idForRecoveryAlert(DateTime localDay) =>
      0x8000000 + localDay.year * 10000 + localDay.month * 100 + localDay.day;
}
