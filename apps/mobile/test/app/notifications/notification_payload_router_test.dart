import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/notifications/notification_payload_router.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/notifications/providers.dart';

void main() {
  test('notificationRouteFromPayload accepts only internal routes', () {
    expect(
      notificationRouteFromPayload(
        ' /knowledge/review?agent_artifact_id=artifact-1 ',
      ),
      '/knowledge/review?agent_artifact_id=artifact-1',
    );
    expect(notificationRouteFromPayload('knowledge/review'), isNull);
    expect(notificationRouteFromPayload('https://example.com/path'), isNull);
    expect(notificationRouteFromPayload('//example.com/path'), isNull);
    expect(notificationRouteFromPayload(''), isNull);
    expect(notificationRouteFromPayload(null), isNull);
  });

  testWidgets('routes live notification payloads through GoRouter', (
    tester,
  ) async {
    final service = _FakeNotificationService();
    addTearDown(service.dispose);
    final router = _testRouter();

    await tester.pumpWidget(_TestApp(router: router, service: service));

    expect(find.text('home'), findsOneWidget);

    service.emit('/knowledge/review?agent_artifact_id=artifact-1');
    await tester.pumpAndSettle();

    expect(find.text('artifact-1'), findsOneWidget);
  });

  testWidgets('routes launch notification payload once on startup', (
    tester,
  ) async {
    final service = _FakeNotificationService(
      launchPayload: '/knowledge/review?agent_artifact_id=launch-artifact',
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

    service.emit('https://example.com/knowledge/review');
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });
}

GoRouter _testRouter() {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const Text('home')),
      GoRoute(
        path: '/knowledge/review',
        builder: (context, state) =>
            Text(state.uri.queryParameters['agent_artifact_id'] ?? 'missing'),
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
