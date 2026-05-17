import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/home/home_page.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 4, 1),
  updatedByDevice: 't',
  hlc: Hlc.zero('t'),
);

Asset _cash(String id) => Asset(
  id: id,
  type: AssetType.cash,
  symbol: id,
  currency: 'CNY',
  sync: _meta(),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Asset-only dashboard: net-worth hero + allocation pie + trend strip,
  // no liabilities. Liabilities trigger `liabilitySummaryProvider`, which
  // chains down to `liabilityRepositoryProvider → appDatabaseProvider →
  // syncEngineProvider`; mocking that whole stack just to get a debt slice
  // on the pie buys nothing visually that the asset slice doesn't already
  // exercise. If we want the "with debt" surface, add a separate variant
  // wired against an in-memory Drift database (see asset_detail_page_test).
  runAllVariants('home_page', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'home_page',
      variant: variant,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        manualAssetsStreamProvider.overrideWith(
          (_) => Stream.value([_cash('cash-1'), _cash('cash-2')]),
        ),
        dashboardManualAssetValuationsProvider.overrideWith(
          (_) => const AsyncValue.data(<ManualAssetValuation>[]),
        ),
        physicalAssetsListProvider.overrideWith(
          (_) => Stream.value(const <PhysicalAsset>[]),
        ),
        liabilitiesStreamProvider.overrideWith((_) => Stream.value(const [])),
        fxRatesStreamProvider.overrideWith(
          (_) => Stream<List<FxRate>>.value(const []),
        ),
        allAssetsStreamProvider.overrideWith(
          (_) => Stream.value(const <Asset>[]),
        ),
        holdingsSnapshotProvider.overrideWith(
          (_) async => const <String, HoldingSnapshot>{},
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
      child: const HomePage(),
    );
  });
}
