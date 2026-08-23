import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/background/background_scheduler.dart';
import 'package:naviwealth/core/notifications/notification_service_stub.dart';

void main() {
  test('global attention notification metadata stays stable', () {
    expect(kLifeAttentionNotificationChannel.id, 'lifeos.attention');
    expect(kLifeAttentionNotificationChannel.name, 'Life Navigator');
    expect(kLifeAttentionNotificationChannel.description, isNotEmpty);
  });

  test('global attention notification id is stable per local date', () {
    final day = DateTime(2026, 6, 20, 23, 59);
    final sameLocalDay = DateTime(2026, 6, 20, 0, 1);

    expect(
      lifeAttentionNotificationId(day),
      lifeAttentionNotificationId(sameLocalDay),
    );
    expect(lifeAttentionNotificationId(day), greaterThanOrEqualTo(0));
    expect(lifeAttentionNotificationId(day), lessThan(0x7fffffff));
  });

  test('unsupported notification service is unavailable and no-ops', () async {
    final service = createNotificationService();

    expect(await service.isAvailable(), isFalse);
    expect(await service.hasPermissions(), isFalse);
    expect(await service.requestPermissions(), isFalse);
    expect(await service.initialPayload(), isNull);
    await expectLater(service.payloads, emitsDone);
    await service.showNow(
      id: 1,
      title: 'Life Navigator',
      body: 'Review the evidence.',
      payload: '/life',
      channel: kLifeAttentionNotificationChannel,
    );
    await service.cancel(1);
  });
}
