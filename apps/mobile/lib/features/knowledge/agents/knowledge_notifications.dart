import '../../../core/notifications/notification_service.dart';
import '../composition/knowledge_route_paths.dart';

const String kKnowledgeAgentArtifactQueryParam = 'agent_artifact_id';

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

  static String payloadForRoutineDigest({required String artifactId}) {
    return Uri(
      path: KnowledgeRoutes.review,
      queryParameters: <String, String>{
        kKnowledgeAgentArtifactQueryParam: artifactId,
      },
    ).toString();
  }

  static String? routineArtifactIdFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final uri = Uri.tryParse(payload);
    if (uri == null || uri.path != KnowledgeRoutes.review) return null;
    if (uri.hasScheme || uri.hasAuthority) return null;
    final artifactId = uri.queryParameters[kKnowledgeAgentArtifactQueryParam];
    return artifactId == null || artifactId.isEmpty ? null : artifactId;
  }
}
