import '../../../core/background/background_scheduler.dart';
import '../composition/health_route_paths.dart';

const String kHealthAgentArtifactQueryParam = 'agent_artifact_id';

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

  static String payloadForRecoveryAlert({required String artifactId}) {
    return Uri(
      path: HealthRoutes.today,
      queryParameters: <String, String>{
        kHealthAgentArtifactQueryParam: artifactId,
      },
    ).toString();
  }

  static String? recoveryArtifactIdFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final uri = Uri.tryParse(payload);
    if (uri == null || uri.path != HealthRoutes.today) return null;
    final artifactId = uri.queryParameters[kHealthAgentArtifactQueryParam];
    return artifactId == null || artifactId.isEmpty ? null : artifactId;
  }
}
