import '../../../core/notifications/notification_service.dart';

const kKnowledgeReviewNotificationChannel = NotificationChannelSpec(
  id: 'lifeos.knowledge.review',
  name: 'Knowledge Review',
  description:
      'KnowledgeOS reminders: due decisions, stale assumptions, and recurring routines.',
);

abstract final class KnowledgeNotifications {
  /// Stable per-day id derived from the local date, offset above HealthOS
  /// ranges so the two never collide in the OS notification list.
  static int idForRoutineDigest(DateTime localDay) =>
      0x10000000 + localDay.year * 10000 + localDay.month * 100 + localDay.day;
}
