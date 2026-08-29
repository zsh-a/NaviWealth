import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_sync_controller.dart';
import 'package:naviwealth/features/health/data/health_sync_status.dart';
import 'package:naviwealth/features/health/data/providers.dart' as health_data;
import 'package:naviwealth/features/health/ui/health_today_page.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('today page uses recovery and weekly domain data once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = makeTestDatabase();
    addTearDown(db.close);
    await DomainOptInStore(db)
        .write(DomainOptIns(const <DomainScope>{DomainScope.health}));

    await tester.pumpWidget(
      _wrap(
        const HealthTodayPage(),
        overrides: _todayOverrides(
          db: db,
          latestDataAt: DateTime.now().toUtc().subtract(
            const Duration(hours: 2),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AdaptiveSummaryGrid), findsOneWidget);
    expect(find.text("Today's Recovery"), findsOneWidget);
    expect(find.text('74'), findsWidgets);
    expect(find.text('Weekly status'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.textContaining('Agent'), findsNothing);

    await tester.tap(find.text('Why this score'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Baseline 52.0'), findsOneWidget);

    await tester.tap(find.text('Data sources'));
    await tester.pumpAndSettle();
    expect(find.text('HealthKit / Health Connect'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Sync'), findsNothing);
  });

  testWidgets('today surfaces a persisted source failure', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = makeTestDatabase();
    addTearDown(db.close);
    await DomainOptInStore(db)
        .write(DomainOptIns(const <DomainScope>{DomainScope.health}));

    final now = DateTime.now().toUtc();
    await tester.pumpWidget(
      _wrap(
        const HealthTodayPage(),
        overrides: _todayOverrides(
          db: db,
          latestDataAt: now.subtract(const Duration(hours: 2)),
          syncStatus: HealthSyncStatus(
            attemptedAt: now.subtract(const Duration(minutes: 5)),
            completedAt: now.subtract(const Duration(minutes: 4)),
            ok: false,
            totalFetched: 0,
            upserted: 0,
            unchanged: 0,
            errorCode: 'health-platform-fetch-failed',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('1 data source failed to refresh'), findsOneWidget);
    expect(find.textContaining('health-platform-fetch-failed'), findsNothing);
  });

  testWidgets('today distinguishes a recent data point from a stale failure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = makeTestDatabase();
    addTearDown(db.close);
    await DomainOptInStore(db)
        .write(DomainOptIns(const <DomainScope>{DomainScope.health}));

    final now = DateTime.now().toUtc();
    await tester.pumpWidget(
      _wrap(
        const HealthTodayPage(),
        overrides: _todayOverrides(
          db: db,
          latestDataAt: now.subtract(const Duration(hours: 2)),
          garminState: GarminConnected(
            lastSyncAt: now.subtract(const Duration(hours: 2)),
            totalMetrics: 12,
            lastErrorCode: 'endpoint_unavailable',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('1 data source failed to refresh'), findsOneWidget);
    expect(find.textContaining('Health data updated'), findsOneWidget);
    expect(find.textContaining('may be out of date'), findsNothing);
  });
}

List<Override> _todayOverrides({
  required AppDatabase db,
  required DateTime? latestDataAt,
  HealthSyncStatus? syncStatus,
  GarminSyncState garminState = const GarminInitial(),
}) => [
  appDatabaseProvider.overrideWith((ref) async => db),
  currentUserIdProvider.overrideWithValue(() async => 'user-1'),
  health_data.garminSyncControllerProvider.overrideWithBuild(
    (_, _) => garminState,
  ),
  health_data.healthSyncStatusProvider.overrideWithValue(syncStatus),
  health_data.healthPlatformStatusProvider.overrideWith(
    (ref) async => const health_data.HealthPlatformStatus(
      available: true,
      permissionsGranted: true,
    ),
  ),
  health_data.healthSourceDataSummaryProvider.overrideWith(
    (ref) async =>
        health_data.HealthSourceDataSummary(platformLatestAt: latestDataAt),
  ),
  healthHasAnyDataProvider.overrideWith((ref) async => true),
  healthTodayMetricGridProvider.overrideWith(
    (ref) async => HealthTodayMetricGridModel.empty(),
  ),
  recoverySignalProvider.overrideWith(
    (ref) async => <String, Object?>{
      'score': 74,
      'verdict': 'steady',
      'confidence': 'high',
      'coverage': 1.0,
      'freshness_hours': 2.0,
      'components': <Object?>[
        <String, Object?>{
          'metric': 'hrv',
          'recent_value': 48.0,
          'baseline_value': 52.0,
          'recent_samples': 6,
          'baseline_samples': 12,
          'delta_pct': -8.0,
          'score': 58.0,
        },
      ],
    },
  ),
  recoverySparklineProvider.overrideWith((ref) async => const <double>[]),
  weeklySummaryProvider.overrideWith(
    (ref) async => const WeeklySummary(
      totalSteps: 70000,
      avgSleepHours: 7.4,
      totalWorkoutMinutes: 180,
      avgHrv: 48,
      avgRhr: 56,
      workoutCount: 3,
    ),
  ),
];

Widget _wrap(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: FTheme(data: FTheme.neutral.light.desktop, child: child),
    ),
  );
}
