/// Web / desktop fallback for [NotificationService]. Same lifecycle
/// shape as the native impl but every call reports unavailable, so
/// callers can fan out to platform-aware logic without an `if (kIsWeb)`
/// at every site.
library;

import 'notification_service.dart';

NotificationService createNotificationService() =>
    const _UnsupportedNotificationService();

class _UnsupportedNotificationService implements NotificationService {
  const _UnsupportedNotificationService();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> hasPermissions() async => false;

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
    NotificationChannelSpec channel = NotificationChannelSpec.healthBriefing,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}
