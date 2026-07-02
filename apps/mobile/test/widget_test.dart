import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/domain_composition.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';
import 'package:naviwealth/features/finance/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/persistence/test_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ai_privacy.onboarding_seen.v1': true,
    });
  });

  testWidgets('NaviWealthApp boots into the home shell', (tester) async {
    // The shell picks bottom nav / side rail / desktop sidebar by viewport width.
    // Pin a mobile-sized surface so this smoke test keeps asserting bottom-nav
    // behavior; the responsive switch is covered in router_test.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          // Production bootstrap uses this bundle so the DomainPack
          // inventory, shell routes, active-domain aggregators, and
          // domain-owned provider seams all stay in sync.
          ...lifeOsDomainCompositionOverrides(),
          // The dashboard subscribes to live DB streams. With no real
          // database in the test environment, short-circuit the streams
          // so the home page resolves to its empty state.
          manualAssetsStreamProvider.overrideWith(
            (ref) => Stream<List<Asset>>.value(const []),
          ),
          physicalAssetsListProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          liabilitiesStreamProvider.overrideWith(
            (ref) => Stream<List<Liability>>.value(const []),
          ),
          accountsStreamProvider.overrideWith(
            (ref) => Stream<List<Account>>.value(const []),
          ),
          // Dashboard's FX-rate converter (FIR-73) reads from a Drift
          // stream; without an override it tries to open the real DB,
          // which fails in widget tests and leaks a pending timer.
          fxRatesStreamProvider.overrideWith(
            (ref) => Stream<List<FxRate>>.value(const []),
          ),
          // Securities holdings now feed the dashboard total — stub so the
          // test never hits the real Drift database / mutation stamper.
          allAssetsStreamProvider.overrideWith(
            (ref) => Stream<List<Asset>>.value(const []),
          ),
          holdingsSnapshotProvider.overrideWith(
            (ref) async => const <String, HoldingSnapshot>{},
          ),
          dashboardPriceRowsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          cashFlowSummaryProvider.overrideWith(
            (ref, request) async => CashFlowSummary(
              period: request.period,
              baseCurrency: 'CNY',
              buckets: const [],
              totalInBase: Money.zero('CNY'),
            ),
          ),
        ],
        child: const NaviWealthApp(),
      ),
    );
    await _pumpFrames(tester);

    // Home page localized nav label — "Today" in en-US (renamed from
    // "Overview" under the IA contract). Test environment falls back to
    // the first supported locale (en).
    expect(find.text('Today'), findsWidgets);
    expect(find.byType(FloatingGlassNavBar), findsOneWidget);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}
