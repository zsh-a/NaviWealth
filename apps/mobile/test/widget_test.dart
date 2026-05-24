import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/liability.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('NaviWealthApp boots into the home shell', (tester) async {
    // The shell picks bottom nav / side rail / desktop sidebar by viewport width.
    // Pin a mobile-sized surface so this smoke test keeps asserting bottom-nav
    // behavior; the responsive switch is covered in router_test.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
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
    expect(find.byType(FBottomNavigationBar), findsOneWidget);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}
