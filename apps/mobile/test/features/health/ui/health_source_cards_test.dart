import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_sync_controller.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_token_store.dart';
import 'package:naviwealth/features/health/data/providers.dart' as health_data;
import 'package:naviwealth/features/health/ui/garmin_account_bind_sheet.dart';
import 'package:naviwealth/features/health/ui/garmin_sync_status_card.dart';
import 'package:naviwealth/features/health/ui/health_domain_settings_page.dart';
import 'package:naviwealth/features/health/ui/health_today_page.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'partial automatic refresh retains source content at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now().toUtc();
      await tester.pumpWidget(
        _wrap(
          const GarminSyncStatusCard(),
          overrides: [
            health_data.garminSyncControllerProvider.overrideWithBuild(
              (ref, build) => GarminSyncing(
                startedAt: now,
                automatic: true,
                previous: GarminConnected(
                  lastSyncAt: now,
                  lastCheckedAt: now,
                  totalMetrics: 2,
                  partial: true,
                  lastErrorCode: 'endpoint_unavailable',
                ),
              ),
            ),
            health_data.healthSourceDataSummaryProvider.overrideWith(
              (ref) async =>
                  health_data.HealthSourceDataSummary(garminLatestAt: now),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('2 updated'), findsOneWidget);
      expect(
        find.text('Updates automatically while the app is open'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('binding starts an import without a second sync tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _BindingController();
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showGarminAccountBindSheet(context: context),
              child: const Text('Bind'),
            ),
          ),
        ),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          health_data.garminSyncControllerProvider.overrideWith(
            () => controller,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bind'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(EditableText).at(0),
      'test@example.invalid',
    );
    await tester.enterText(find.byType(EditableText).at(1), 'test-password');
    await tester.tap(find.text('Connect').last);
    await tester.pumpAndSettle();
    expect(controller.imports, 1);
    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HealthOS source cards stay readable at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = makeTestDatabase();
    addTearDown(db.close);
    await DomainOptInStore(db)
        .write(DomainOptIns(const <DomainScope>{DomainScope.health}));

    await tester.pumpWidget(
      _wrap(
        const HealthTodayPage(),
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          healthHasAnyDataProvider.overrideWith((ref) async => true),
          healthHasRecoveryInputsProvider.overrideWith((ref) async => true),
          healthTodayMetricGridProvider.overrideWith(
            (ref) async => HealthTodayMetricGridModel.empty(),
          ),
          recoverySignalProvider.overrideWith(
            (ref) async => <String, Object?>{
              'score': 74,
              'verdict': 'steady',
              'confidence': 'high',
              'coverage': 1.0,
            },
          ),

          weeklySummaryProvider.overrideWith((ref) async => null),
          health_data.garminSyncControllerProvider.overrideWithBuild(
            (ref, build) => const GarminInitial(),
          ),
          health_data.healthPlatformStatusProvider.overrideWith(
            (ref) async => const health_data.HealthPlatformStatus(
              available: true,
              permissionsGranted: true,
            ),
          ),
          health_data.healthSyncStatusProvider.overrideWithValue(null),
          health_data.healthSourceDataSummaryProvider.overrideWith(
            (ref) async => const health_data.HealthSourceDataSummary(),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Data sources'));
    await tester.pumpAndSettle();

    expect(find.text('HealthKit / Health Connect'), findsOneWidget);
    expect(find.text('Garmin Connect'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Garmin failure details do not overflow at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.utc(2026, 8, 27, 12);
    await tester.pumpWidget(
      _wrap(
        const GarminSyncStatusCard(),
        overrides: [
          health_data.garminSyncControllerProvider.overrideWithBuild(
            (ref, build) => GarminConnected(
              lastSyncAt: now.subtract(const Duration(hours: 2)),
              totalMetrics: 32,
              lastAttemptAt: now.subtract(const Duration(minutes: 5)),
              lastErrorCode: 'endpoint_unavailable',
            ),
          ),
          health_data.healthSourceDataSummaryProvider.overrideWith(
            (ref) async => health_data.HealthSourceDataSummary(
              garminLatestAt: now.subtract(const Duration(hours: 2)),
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Garmin Connect'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings reports a failed platform check as unavailable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const HealthDomainSettingsPage(),
        overrides: [
          health_data.healthPlatformStatusProvider.overrideWith(
            (ref) async => const health_data.HealthPlatformStatus.failed(),
          ),
          health_data.healthSyncStatusProvider.overrideWithValue(null),
          health_data.healthSourceDataSummaryProvider.overrideWith(
            (ref) async => const health_data.HealthSourceDataSummary(),
          ),
          health_data.garminSyncControllerProvider.overrideWithBuild(
            (ref, build) => const GarminInitial(),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Checking connection…'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
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

class _BindingController extends GarminSyncController {
  int imports = 0;
  @override
  GarminSyncState build() => const GarminInitial();
  @override
  Future<GarminSavedCredentials?> loadSavedCredentials() async => null;
  @override
  Future<void> connect(
    String email,
    String password, {
    required bool rememberPassword,
  }) async {
    state = const GarminConnected();
  }

  @override
  Future<health_data.HealthRefreshSourceResult> syncNow({
    Duration window = const Duration(days: 30),
    bool automatic = false,
  }) async {
    imports++;
    return const health_data.HealthRefreshSourceResult(
      source: health_data.HealthRefreshSource.garmin,
      outcome: health_data.HealthRefreshOutcome.synced,
    );
  }
}
