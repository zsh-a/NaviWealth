import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/notifications/notification_service_stub.dart';

void main() {
  test('health notification ids are stable per local day', () {
    final day = DateTime(2026, 6, 20, 8);
    expect(HealthNotifications.idForBriefing(day), 20260620);
    expect(
      HealthNotifications.idForRecoveryAlert(day),
      isNot(HealthNotifications.idForBriefing(day)),
    );
    expect(
      HealthNotifications.idForRecoveryAlert(day),
      HealthNotifications.idForRecoveryAlert(DateTime(2026, 6, 20, 23)),
    );
  });

  test('knowledge notification ids never collide with health ids', () {
    final day = DateTime(2026, 6, 20);
    final ids = {
      HealthNotifications.idForBriefing(day),
      HealthNotifications.idForRecoveryAlert(day),
      KnowledgeNotifications.idForRoutineDigest(day),
    };
    expect(ids, hasLength(3));
  });

  test('channel specs expose stable platform ids', () {
    expect(
      NotificationChannelSpec.healthBriefing.id,
      HealthNotifications.channelId,
    );
    expect(
      NotificationChannelSpec.knowledgeReview.id,
      'lifeos.knowledge.review',
    );
  });

  test(
    'unsupported notification service is a no-op unavailable service',
    () async {
      final service = createNotificationService();

      expect(await service.isAvailable(), isFalse);
      expect(await service.hasPermissions(), isFalse);
      expect(await service.requestPermissions(), isFalse);
      await service.showNow(id: 1, title: 'Title', body: 'Body');
      await service.cancel(1);
    },
  );
}
