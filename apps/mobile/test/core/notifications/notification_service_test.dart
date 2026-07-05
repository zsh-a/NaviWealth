import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/notifications/notification_service_stub.dart';
import 'package:naviwealth/features/health/agents/health_notifications.dart';
import 'package:naviwealth/features/knowledge/agents/knowledge_notifications.dart';

void main() {
  test('notification channel metadata stays stable', () {
    expect(kHealthBriefingNotificationChannel.id, 'lifeos.health.briefing');
    expect(kHealthBriefingNotificationChannel.name, 'Morning Briefing');
    expect(
      kHealthBriefingNotificationChannel.description,
      'Daily HealthOS morning briefing summaries.',
    );

    expect(kKnowledgeReviewNotificationChannel.id, 'lifeos.knowledge.review');
    expect(kKnowledgeReviewNotificationChannel.name, 'Knowledge Review');
    expect(
      kKnowledgeReviewNotificationChannel.description,
      'KnowledgeOS reminders: due decisions, stale assumptions, and recurring routines.',
    );
  });

  test('notification channel ids are unique and Android-safe', () {
    final ids = <String>{};

    for (final spec in _knownDomainChannels) {
      expect(spec.id, isNotEmpty, reason: spec.name);
      expect(spec.id, matches(RegExp(r'^[a-z0-9.]+$')), reason: spec.id);
      expect(ids.add(spec.id), isTrue, reason: 'Duplicate channel ${spec.id}');
      expect(spec.name, isNotEmpty, reason: spec.id);
      expect(spec.description, isNotEmpty, reason: spec.id);
    }
  });

  test(
    'health notification ids are stable per local date and non-colliding',
    () {
      final day = DateTime(2026, 6, 20, 23, 59);
      final sameLocalDay = DateTime(2026, 6, 20, 0, 1);

      expect(HealthNotifications.idForBriefing(day), 20260620);
      expect(
        HealthNotifications.idForBriefing(day),
        HealthNotifications.idForBriefing(sameLocalDay),
      );
      expect(HealthNotifications.idForRecoveryAlert(day), 0x8000000 + 20260620);
      expect(
        HealthNotifications.idForRecoveryAlert(day),
        isNot(HealthNotifications.idForBriefing(day)),
      );
    },
  );

  test('knowledge notification ids are stable and outside health ranges', () {
    final day = DateTime(2026, 6, 20);

    expect(
      KnowledgeNotifications.idForRoutineDigest(day),
      0x10000000 + 20260620,
    );
    expect(
      KnowledgeNotifications.idForRoutineDigest(day),
      isNot(HealthNotifications.idForBriefing(day)),
    );
    expect(
      KnowledgeNotifications.idForRoutineDigest(day),
      isNot(HealthNotifications.idForRecoveryAlert(day)),
    );
  });

  test('knowledge routine notification payload deep-links to artifact', () {
    final payload = KnowledgeNotifications.payloadForRoutineDigest(
      artifactId: 'knowledge_routine_due:2026-07-05',
    );

    expect(
      payload,
      '/knowledge/review?agent_artifact_id=knowledge_routine_due%3A2026-07-05',
    );
    expect(
      KnowledgeNotifications.routineArtifactIdFromPayload(payload),
      'knowledge_routine_due:2026-07-05',
    );
    expect(
      KnowledgeNotifications.routineArtifactIdFromPayload(
        '/knowledge/review?agent_artifact_id=',
      ),
      isNull,
    );
    expect(
      KnowledgeNotifications.routineArtifactIdFromPayload('/knowledge'),
      isNull,
    );
  });

  test('notification ids stay within Android signed int range', () {
    final representativeDays = [DateTime(2026, 1, 1), DateTime(2099, 12, 31)];

    for (final day in representativeDays) {
      final ids = [
        HealthNotifications.idForBriefing(day),
        HealthNotifications.idForRecoveryAlert(day),
        KnowledgeNotifications.idForRoutineDigest(day),
      ];

      for (final id in ids) {
        expect(id, greaterThanOrEqualTo(0), reason: day.toIso8601String());
        expect(id, lessThan(0x7fffffff), reason: day.toIso8601String());
      }
      expect(ids.toSet(), hasLength(ids.length));
    }
  });

  test('unsupported notification service is unavailable and no-ops', () async {
    final service = createNotificationService();

    expect(await service.isAvailable(), isFalse);
    expect(await service.hasPermissions(), isFalse);
    expect(await service.requestPermissions(), isFalse);
    await service.showNow(
      id: 1,
      title: 'Title',
      body: 'Body',
      channel: kHealthBriefingNotificationChannel,
    );
    await service.showNow(
      id: 2,
      title: 'Knowledge',
      body: 'Review',
      payload: 'payload',
      channel: kKnowledgeReviewNotificationChannel,
    );
    await service.cancel(1);
  });
}

const List<NotificationChannelSpec> _knownDomainChannels =
    <NotificationChannelSpec>[
      kHealthBriefingNotificationChannel,
      kKnowledgeReviewNotificationChannel,
    ];
