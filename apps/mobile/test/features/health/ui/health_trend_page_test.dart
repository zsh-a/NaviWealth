import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/data/health_series_providers.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';
import 'package:naviwealth/features/health/ui/body_measurement_entry_sheet.dart';
import 'package:naviwealth/features/health/ui/health_metric_detail.dart';
import 'package:naviwealth/features/health/ui/health_today_page.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/features/health/ui/health_trend_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'health_test_fixture.dart';

Future<GoRouter> _pump(
  WidgetTester tester,
  HealthTestFixture fixture, {
  String location = '/health/trend',
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/health', builder: (_, _) => const HealthTodayPage()),
      GoRoute(
        path: '/health/trend',
        builder: (_, state) =>
            HealthTrendPage.fromQuery(state.uri.queryParameters),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: fixture.overrides,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: FTheme(
            data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'overview drills into one metric; window and back preserve URL state',
    (tester) async {
      final f = await HealthTestFixture.create();
      addTearDown(f.db.close);
      final router = await _pump(tester, f);
      expect(find.byType(HealthMetricDetail), findsNothing);
      expect(
        find.byKey(const ValueKey('health-trend-hrvDaily')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('health-trend-hrvDaily')));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['metric'],
        'hrv_daily',
      );
      expect(find.byType(HealthMetricDetail), findsOneWidget);
      final line = tester.widget<NwLineChart>(find.byType(NwLineChart).first);
      expect(line.series.length, 2, reason: 'missing HRV dates split the line');
      expect(line.minX, isNotNull);
      expect(line.maxX, isNotNull);
      await tester.tap(find.text('7d'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.queryParameters, {
        'metric': 'hrv_daily',
        'window': '7',
      });
      await tester.tap(find.text('All metrics'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.queryParameters, {
        'window': '7',
      });
      expect(find.byType(HealthMetricDetail), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('single body measurement is visible and editable in place', (
    tester,
  ) async {
    final f = await HealthTestFixture.create();
    addTearDown(f.db.close);
    await _pump(tester, f, location: '/health/trend?group=body&metric=weight');
    expect(find.text('72.5 kg'), findsWidgets);
    expect(
      find.byType(NwLineChart),
      findsNothing,
      reason: 'one measurement is readable without an oversized empty chart',
    );
    await tester.tap(find.text('Manual').first);
    await tester.pumpAndSettle();
    expect(find.text('Morning measurement'), findsOneWidget);
    await tester.ensureVisible(find.text('Edit measurement'));
    await tester.tap(find.text('Edit measurement'));
    await tester.pumpAndSettle();
    expect(find.byType(BodyMeasurementEntrySheet), findsOneWidget);
    await tester.enterText(find.byType(EditableText).first, '71.8');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('71.8 kg'), findsWidgets);
    expect(
      (await f.repo.listByKind(
        ownerUserId: HealthTestFixture.owner,
        kind: HealthMetricKind.weight,
      )).length,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty body-fat detail opens correct form and keeps per-kind drafts',
    (tester) async {
      final f = await HealthTestFixture.create(populated: false);
      addTearDown(f.db.close);
      await _pump(tester, f, location: '/health/trend?metric=body_fat');
      await tester.tap(find.text('Record body metric').last);
      await tester.pumpAndSettle();
      var field = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(field.controller.text, isEmpty);
      await tester.enterText(find.byType(EditableText).first, '0.5');
      await tester.tap(find.text('Weight').first);
      await tester.pumpAndSettle();
      field = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(field.controller.text, isEmpty);
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedRow<HealthMetricKind>),
          matching: find.text('Body fat'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        '0.5',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        (await f.repo.listByKind(
          ownerUserId: HealthTestFixture.owner,
          kind: HealthMetricKind.bodyFat,
        )).single.value,
        0.005,
      );
    },
  );

  testWidgets('calendar range queries do not truncate dense activity data', (
    tester,
  ) async {
    final f = await HealthTestFixture.create(populated: false);
    addTearDown(f.db.close);
    for (var i = 0; i < 180; i++) {
      final at = HealthTestFixture.now.subtract(Duration(hours: i * 6));
      await f.repo.upsert(
        f.metric('workout:$i', HealthMetricKind.workoutSession, at, 1200),
      );
    }
    await _pump(
      tester,
      f,
      location: '/health/trend?metric=workout_session&window=90',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HealthTrendPage)),
    );
    final series = await container.read(
      healthTrendSeriesProvider((group: TrendGroup.activity, windowDays: 90))
          .future,
    );
    expect(
      series[HealthMetricKind.workoutSession]!.samples.fold<int>(
        0,
        (n, s) => n + s.records.length,
      ),
      180,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today and Trends use the same sleep daily aggregate', (
    tester,
  ) async {
    final f = await HealthTestFixture.create();
    addTearDown(f.db.close);
    await f.repo.upsert(
      f.metric(
        'garmin:nap',
        HealthMetricKind.sleepSession,
        DateTime(2026, 9, 12, 10).toUtc(),
        1800,
      ),
    );
    await _pump(tester, f);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HealthTrendPage)),
    );
    final today = await container.read(healthTodayMetricGridProvider.future);
    final trends = await container.read(
      healthTrendSeriesProvider((group: TrendGroup.recovery, windowDays: 7))
          .future,
    );
    expect(today.series[HealthMetricKind.sleepSession]!.latest!.value, 7.5);
    expect(trends[HealthMetricKind.sleepSession]!.latest!.value, 7.5);
  });

  for (final location in [
    '/health',
    '/health/trend',
    '/health/trend?metric=sleep_session',
    '/health/trend?metric=weight',
  ]) {
    testWidgets('narrow large-text layout $location has no overflow', (
      tester,
    ) async {
      final f = await HealthTestFixture.create();
      addTearDown(f.db.close);
      await _pump(tester, f, location: location, width: 320, scale: 2);
      expect(tester.takeException(), isNull);
    });
  }
}
