import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/activation/data/finance_activation_providers.dart';
import 'package:naviwealth/features/finance/activation/domain/finance_activation.dart';
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
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/ui/home_page.dart';
import 'package:naviwealth/features/finance/ingest/data/providers.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:naviwealth/features/finance/runway/data/money_runway_providers.dart';
import 'package:naviwealth/features/finance/runway/domain/money_runway.dart';
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

CategoryItem _categoryItem({
  required String id,
  required String name,
  required String amount,
}) => CategoryItem(
  id: id,
  name: name,
  subtitle: null,
  valueInBase: Money(_d(amount), 'CNY'),
  nativeAmount: _d(amount),
  nativeCurrency: 'CNY',
);

DashboardSnapshot _establishedSnapshot() => DashboardSnapshot(
  asOf: _goldenNow,
  baseCurrency: 'CNY',
  allocations: [
    CategoryAllocation(
      category: AssetCategory.stock,
      totalInBase: Money(_d('620000'), 'CNY'),
      items: [
        _categoryItem(id: 'stock-1', name: 'Core portfolio', amount: '620000'),
      ],
    ),
    CategoryAllocation(
      category: AssetCategory.cash,
      totalInBase: Money(_d('180000'), 'CNY'),
      items: [
        _categoryItem(id: 'cash-1', name: 'Emergency fund', amount: '180000'),
      ],
    ),
    CategoryAllocation(
      category: AssetCategory.liability,
      totalInBase: Money(_d('100000'), 'CNY'),
      items: [_categoryItem(id: 'loan-1', name: 'Home loan', amount: '100000')],
    ),
  ],
  totalAssets: Money(_d('800000'), 'CNY'),
  totalLiabilities: Money(_d('100000'), 'CNY'),
  netWorth: Money(_d('700000'), 'CNY'),
);

Account _activityAccount({
  required String id,
  required String name,
  required AccountSide side,
}) => Account(
  id: id,
  type: AccountCategory.bank,
  name: name,
  currency: 'CNY',
  category: side,
  sync: _meta(),
);

JournalEntryWithPostings _activityEntry({
  required String id,
  required String narration,
  required String amount,
  required int day,
}) => JournalEntryWithPostings(
  entry: JournalEntry(
    id: id,
    date: DateTime.utc(2026, 5, day, 10),
    narration: narration,
    sync: _meta(),
  ),
  postings: [
    Posting(
      id: '$id-expense',
      journalEntryId: id,
      position: 0,
      accountId: 'expenses:daily',
      units: _d(amount),
      unit: 'CNY',
      sync: _meta(),
    ),
    Posting(
      id: '$id-bank',
      journalEntryId: id,
      position: 1,
      accountId: 'assets:bank',
      units: -_d(amount),
      unit: 'CNY',
      sync: _meta(),
    ),
  ],
);

ActivityFeedPage _establishedActivityFeed() {
  final accounts = [
    _activityAccount(
      id: 'assets:bank',
      name: 'Daily account',
      side: AccountSide.asset,
    ),
    _activityAccount(
      id: 'expenses:daily',
      name: 'Daily spending',
      side: AccountSide.expense,
    ),
  ];
  final entries = [
    _activityEntry(
      id: 'entry-3',
      narration: 'Weekly groceries',
      amount: '386',
      day: 17,
    ),
    _activityEntry(
      id: 'entry-2',
      narration: 'Family dinner',
      amount: '268',
      day: 16,
    ),
    _activityEntry(
      id: 'entry-1',
      narration: 'Morning coffee',
      amount: '32',
      day: 15,
    ),
  ];
  return ActivityFeedPage(
    entries: entries,
    totalCount: entries.length,
    hasMore: false,
    isFiltered: false,
    accountsById: {for (final account in accounts) account.id: account},
  );
}

DashboardHeaderMetrics _headerMetrics() => DashboardHeaderMetrics(
  baseCurrency: 'CNY',
  dailyChange: Money(_d('1280'), 'CNY'),
  monthlyChange: Money(_d('16800'), 'CNY'),
  monthlyChangePct: 0.0246,
  ytdChange: Money(_d('58800'), 'CNY'),
  ytdChangePct: 0.0917,
);

DashboardDailyChange _dailyChange() =>
    DashboardDailyChange(baseCurrency: 'CNY', change: Money(_d('1280'), 'CNY'));

List<Override> _homeOverrides(
  SharedPreferences prefs, {
  DashboardSnapshot? snapshot,
  ActivityFeedPage? activityFeed,
}) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  financeActivationProvider.overrideWith(
    (_) => AsyncValue.data(
      FinanceActivationSnapshot(
        stage: snapshot == null
            ? FinanceActivationStage.addData
            : FinanceActivationStage.complete,
        hasLedgerData: snapshot != null,
        pendingReviewCount: 0,
        runway: null,
      ),
    ),
  ),
  ingestDraftProgressProvider.overrideWith(
    (_) => Stream.value(const IngestDraftProgress.empty()),
  ),
  moneyRunwayProvider.overrideWith(
    (_) => AsyncValue.data(
      buildMoneyRunway(
        asOf: _goldenNow,
        currency: 'CNY',
        startingBalance: _d('180000'),
        reserveTarget: _d('57600'),
        averageMonthlyExpense: _d('19200'),
        estimatedDailyVariableOutflow: _d('640'),
        scheduledFlows: const <RunwayScheduledFlow>[],
        confidence: MoneyRunwayConfidence.medium,
        dataCompleteness: 0.75,
        hasData: snapshot != null,
      ),
    ),
  ),
  cashFlowNowProvider.overrideWithValue(_goldenNow),
  dashboardSnapshotProvider.overrideWith(
    (_) async =>
        snapshot ??
        DashboardSnapshot.empty(asOf: _goldenNow, baseCurrency: 'CNY'),
  ),
  dashboardHeaderMetricsProvider.overrideWith((_) async => _headerMetrics()),
  dashboardDailyChangeProvider.overrideWith((_) async => _dailyChange()),
  activityFeedProvider.overrideWith(
    (_) => Stream.value(
      activityFeed ??
          const ActivityFeedPage(
            entries: [],
            totalCount: 0,
            hasMore: false,
            isFiltered: false,
            accountsById: {},
          ),
    ),
  ),
  activityFeedPreviewProvider.overrideWith(
    (_) => Stream.value(
      activityFeed ??
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
    expect(find.text('Import statements'), findsOneWidget);
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
      expect(find.text('Import statements'), findsOneWidget);
    },
  );

  for (final profile in [
    ResponsiveGoldenProfile.narrow,
    ResponsiveGoldenProfile.wide,
  ]) {
    final suffix = profile == ResponsiveGoldenProfile.narrow
        ? 'narrow'
        : 'wide';
    runResponsiveGolden(
      'home_page established — $suffix',
      profile: profile,
      body: (tester, profile) async {
        final prefs = await SharedPreferences.getInstance();
        await pumpAndSnapshotResponsive(
          tester,
          name: 'home_page_established_$suffix',
          profile: profile,
          overrides: _homeOverrides(
            prefs,
            snapshot: _establishedSnapshot(),
            activityFeed: _establishedActivityFeed(),
          ),
          child: const HomePage(),
        );

        expect(find.text('Record entry'), findsOneWidget);
        expect(find.text('Transfer'), findsOneWidget);
        expect(find.text('Weekly groceries'), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('cashflow-balance-bar')))
              .width,
          greaterThan(200),
        );
      },
    );
  }
}
