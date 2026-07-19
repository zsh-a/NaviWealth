import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/ui/home_page.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
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

final _goldenNow = DateTime.utc(2026, 5, 17);

Decimal _d(String value) => Decimal.parse(value);

String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';

DateTime _addMonths(DateTime date, int delta) {
  final monthIndex = date.year * 12 + date.month - 1 + delta;
  final year = monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  return DateTime.utc(year, month, 1);
}

CashFlowBucket _bucket({
  required String key,
  required CashFlowKind kind,
  required String amount,
}) {
  final parsed = _d(amount);
  return CashFlowBucket(
    key: key,
    kind: kind,
    currency: 'CNY',
    totalInBase: Money(parsed, 'CNY'),
    originalTotal: Money(parsed, 'CNY'),
    count: 1,
  );
}

CashFlowSummary _homeCashFlowSummary(CashFlowPeriod period) {
  final current = _monthKey(_goldenNow);
  final previous = _monthKey(_addMonths(_goldenNow, -1));
  final twoBack = _monthKey(_addMonths(_goldenNow, -2));
  return CashFlowSummary(
    period: period,
    baseCurrency: 'CNY',
    buckets: [
      _bucket(key: twoBack, kind: CashFlowKind.salary, amount: '31000'),
      _bucket(key: twoBack, kind: CashFlowKind.expense, amount: '-17800'),
      _bucket(key: twoBack, kind: CashFlowKind.dividend, amount: '880'),
      _bucket(key: previous, kind: CashFlowKind.salary, amount: '32000'),
      _bucket(key: previous, kind: CashFlowKind.expense, amount: '-18600'),
      _bucket(key: previous, kind: CashFlowKind.interest, amount: '210'),
      _bucket(key: current, kind: CashFlowKind.salary, amount: '32000'),
      _bucket(key: current, kind: CashFlowKind.expense, amount: '-19200'),
      _bucket(key: current, kind: CashFlowKind.dividend, amount: '1260'),
      _bucket(key: current, kind: CashFlowKind.interest, amount: '220'),
    ],
    totalInBase: Money(_d('48010'), 'CNY'),
  );
}

ProjectedDividend _homeDividendForecast() {
  return ProjectedDividend(
    assetId: 'portfolio',
    perAsset: {DateTime.utc(2026, 6, 15): _d('1280')},
    total: _d('8400'),
    currency: 'CNY',
    strategy: 'ttm',
    confidence: DividendForecastConfidence.medium,
  );
}

List<Override> _homeOverrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  cashFlowNowProvider.overrideWithValue(_goldenNow),
  dashboardSnapshotProvider.overrideWith(
    (_) async => DashboardSnapshot.empty(asOf: _goldenNow, baseCurrency: 'CNY'),
  ),
  activityFeedProvider.overrideWith(
    (_) => Stream.value(
      const ActivityFeedPage(
        entries: [],
        totalCount: 0,
        hasMore: false,
        isFiltered: false,
        accountsById: {},
      ),
    ),
  ),
  recurringMaterialiseDueProvider.overrideWith((ref, now) async => 0),
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
  allAssetsStreamProvider.overrideWith((_) => Stream.value(const <Asset>[])),
  holdingsSnapshotProvider.overrideWith(
    (_) async => const <String, HoldingSnapshot>{},
  ),
  cashFlowSummaryProvider.overrideWith(
    (ref, request) async => _homeCashFlowSummary(request.period),
  ),
  dividendForecast12mProvider.overrideWith(
    (ref) async => _homeDividendForecast(),
  ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Lock the actual first-use dashboard rather than the transient loading
  // skeleton. The direct snapshot override keeps the target state
  // deterministic while the supporting providers below populate the
  // secondary home modules.
  runAllVariants('home_page', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'home_page',
      variant: variant,
      overrides: _homeOverrides(prefs),
      child: const HomePage(),
    );

    expect(find.text('Add account'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
  });

  runResponsiveGolden(
    'home_page onboarding — wide',
    profile: ResponsiveGoldenProfile.wide,
    body: (tester, profile) async {
      final prefs = await SharedPreferences.getInstance();
      await pumpAndSnapshotResponsive(
        tester,
        name: 'home_page_onboarding_wide',
        profile: profile,
        overrides: _homeOverrides(prefs),
        child: const HomePage(),
      );

      expect(find.text('Add account'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    },
  );
}
