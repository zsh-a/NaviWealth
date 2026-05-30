// Flow-test harness (Task-oriented testing — see docs/testing-strategy.md §4).
//
// Flow tests exercise a *user task* across multiple screens, asserted
// through Page Objects (support/page_objects.dart) rather than raw
// `find.text(...)` calls. The point is durability: when the responsive
// layout is refactored, only the Page Objects change — the Task logic
// in the `*_flow_test.dart` files stays put.
//
// This harness boots the real `NaviWealthApp` (real router, real shell,
// real widgets) with the data layer overridden to deterministic streams,
// reusing the proven override set from test/widget_test.dart. It runs
// under `flutter test` (no device/emulator). The on-device
// `integration_test/` layer that exercises SQLCipher + a real Drift
// connection is the documented next step (docs/testing-strategy.md §6).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/liability.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deterministic seed data for a flow. Defaults to an empty portfolio
/// (the "first run" state); pass non-empty lists to drive Tasks that
/// assert on rendered balances.
class FlowSeed {
  const FlowSeed({
    this.accounts = const [],
    this.manualAssets = const [],
    this.liabilities = const [],
  });

  final List<Account> accounts;
  final List<Asset> manualAssets;
  final List<Liability> liabilities;
}

/// Boots `NaviWealthApp` on a phone-sized surface and pumps it to a
/// settled frame. Returns once the home shell is interactive.
///
/// [extraOverrides] are appended after the base overrides, so a flow can
/// replace any provider it needs without rewriting the boot sequence.
Future<void> bootApp(
  WidgetTester tester, {
  FlowSeed seed = const FlowSeed(),
  List<Override> extraOverrides = const [],
}) async {
  // Phone surface so the shell renders the bottom navigation bar; the
  // responsive rail/sidebar switch is covered in app/router_test.dart.
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // The DomainPack registry contributes the per-domain shell routes
        // (D-1.8 / D-2.3b). bootstrap.dart populates it in production; the
        // default is empty, so without this the `/` route 404s.
        domainPackRegistryProvider.overrideWithValue(kAllDomainPacks),
        // Data layer → deterministic streams. Seeded from [FlowSeed] so a
        // Task can assert on rendered balances without touching Drift.
        manualAssetsStreamProvider.overrideWith(
          (ref) => Stream<List<Asset>>.value(seed.manualAssets),
        ),
        allAssetsStreamProvider.overrideWith(
          (ref) => Stream<List<Asset>>.value(seed.manualAssets),
        ),
        physicalAssetsListProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
        liabilitiesStreamProvider.overrideWith(
          (ref) => Stream<List<Liability>>.value(seed.liabilities),
        ),
        accountsStreamProvider.overrideWith(
          (ref) => Stream<List<Account>>.value(seed.accounts),
        ),
        fxRatesStreamProvider.overrideWith(
          (ref) => Stream<List<FxRate>>.value(const []),
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
        ...extraOverrides,
      ],
      child: const NaviWealthApp(),
    ),
  );
  await settle(tester);
}

/// Pumps a bounded number of frames. Flow surfaces subscribe to streams
/// and timers, so `pumpAndSettle` can hang — pump a fixed budget instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}
