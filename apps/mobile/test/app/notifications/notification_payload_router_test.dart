import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/notifications/notification_payload_router.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/notifications/providers.dart';
import 'package:naviwealth/features/health/agents/health_notifications.dart';
import 'package:naviwealth/features/knowledge/agents/knowledge_notifications.dart';

void main() {
  test('notificationRouteFromPayload accepts only internal routes', () {
    expect(
      notificationRouteFromPayload(' /insights/artifact-1 '),
      '/insights/artifact-1',
    );
    expect(notificationRouteFromPayload('insights/artifact-1'), isNull);
    expect(notificationRouteFromPayload('https://example.com/path'), isNull);
    expect(notificationRouteFromPayload('//example.com/path'), isNull);
    expect(notificationRouteFromPayload(''), isNull);
    expect(notificationRouteFromPayload(null), isNull);
  });

  test('domain notification producers emit accepted internal routes', () {
    final payloads = <String>[
      HealthNotifications.payloadForArtifact('health:artifact-1'),
      KnowledgeNotifications.payloadForArtifact('knowledge:artifact-1'),
    ];

    for (final payload in payloads) {
      expect(notificationRouteFromPayload(payload), payload);
    }
  });

  testWidgets('routes live notification payloads through GoRouter', (
    tester,
  ) async {
    final service = _FakeNotificationService();
    addTearDown(service.dispose);
    final router = _testRouter();

    await tester.pumpWidget(_TestApp(router: router, service: service));

    expect(find.text('home'), findsOneWidget);

    service.emit('/insights/artifact-1');
    await tester.pumpAndSettle();

    expect(find.text('artifact-1'), findsOneWidget);
  });

  testWidgets('routes launch notification payload once on startup', (
    tester,
  ) async {
    final service = _FakeNotificationService(
      launchPayload: '/insights/launch-artifact',
    );
    addTearDown(service.dispose);
    final router = _testRouter();

    await tester.pumpWidget(_TestApp(router: router, service: service));
    await tester.pumpAndSettle();

    expect(find.text('launch-artifact'), findsOneWidget);
  });

  testWidgets('ignores external notification payloads', (tester) async {
    final service = _FakeNotificationService();
    addTearDown(service.dispose);
    final router = _testRouter();

    await tester.pumpWidget(_TestApp(router: router, service: service));

    service.emit('https://example.com/insights/artifact-1');
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });
}

GoRouter _testRouter() {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const Text('home')),
      GoRoute(
        path: '/insights/:artifactId',
        builder: (context, state) =>
            Text(state.pathParameters['artifactId'] ?? 'missing'),
      ),
    ],
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.router, required this.service});

  final GoRouter router;
  final NotificationService service;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [notificationServiceProvider.overrideWithValue(service)],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => NotificationPayloadRouteListener(
          router: router,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _FakeNotificationService implements NotificationService {
  _FakeNotificationService({this.launchPayload});

  final String? launchPayload;
  final StreamController<String> _payloads =
      StreamController<String>.broadcast();

  @override
  Stream<String> get payloads => _payloads.stream;

  void emit(String payload) => _payloads.add(payload);

  Future<void> dispose() async => _payloads.close();

  @override
  Future<String?> initialPayload() async => launchPayload;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required NotificationChannelSpec channel,
    String? payload,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}
