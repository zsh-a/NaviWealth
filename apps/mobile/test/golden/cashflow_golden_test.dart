import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_event.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/cashflow/ui/cashflow_page.dart';
import 'package:naviwealth/features/finance/cashflow/ui/dividend_center_page.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/fifo_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis_engine.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/ui/corporate_action_entry_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

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
  int count = 1,
}) {
  final parsed = _d(amount);
  return CashFlowBucket(
    key: key,
    kind: kind,
    currency: 'USD',
    totalInBase: Money(parsed, 'USD'),
    originalTotal: Money(parsed, 'USD'),
    count: count,
  );
}

CashFlowSummary _cashFlowSummary(CashFlowPeriod period) {
  if (period != CashFlowPeriod.month) {
    return CashFlowSummary(
      period: period,
      baseCurrency: 'USD',
      buckets: const [],
      totalInBase: Money.zero('USD'),
    );
  }

  final current = _monthKey(_goldenNow);
  final previous = _monthKey(_addMonths(_goldenNow, -1));
  final twoBack = _monthKey(_addMonths(_goldenNow, -2));
  final threeBack = _monthKey(_addMonths(_goldenNow, -3));
  return CashFlowSummary(
    period: period,
    baseCurrency: 'USD',
    buckets: [
      _bucket(key: threeBack, kind: CashFlowKind.salary, amount: '5800'),
      _bucket(key: threeBack, kind: CashFlowKind.expense, amount: '-3350'),
      _bucket(key: threeBack, kind: CashFlowKind.dividend, amount: '140'),
      _bucket(key: twoBack, kind: CashFlowKind.salary, amount: '6100'),
      _bucket(key: twoBack, kind: CashFlowKind.expense, amount: '-3650'),
      _bucket(key: twoBack, kind: CashFlowKind.interest, amount: '42'),
      _bucket(key: previous, kind: CashFlowKind.salary, amount: '6200'),
      _bucket(key: previous, kind: CashFlowKind.expense, amount: '-3720'),
      _bucket(key: previous, kind: CashFlowKind.dividend, amount: '180'),
      _bucket(key: current, kind: CashFlowKind.salary, amount: '6200'),
      _bucket(key: current, kind: CashFlowKind.expense, amount: '-3890'),
      _bucket(key: current, kind: CashFlowKind.dividend, amount: '220'),
      _bucket(key: current, kind: CashFlowKind.interest, amount: '76'),
    ],
    totalInBase: Money(_d('7998'), 'USD'),
  );
}

CashFlowEvent _dividendEvent({
  required String id,
  required DateTime date,
  required String amount,
}) {
  final parsed = _d(amount);
  return CashFlowEvent(
    journalEntryId: id,
    date: date,
    kind: CashFlowKind.dividend,
    signedAmount: parsed,
    originalAmount: parsed,
    currency: 'USD',
    accountId: 'brokerage-cash',
    counterAccountSide: AccountSide.income,
  );
}

DividendCenterSnapshot _dividendSnapshot() {
  final events = [
    DividendCenterEvent(
      event: _dividendEvent(
        id: 'div-1',
        date: DateTime.utc(2026, 5, 10),
        amount: '176',
      ),
      assetId: 'US:AAPL',
      assetLabel: 'Apple Inc.',
      withholdingInBase: _d('44'),
      withholdingOriginal: _d('44'),
      withholdingCurrency: 'USD',
    ),
    DividendCenterEvent(
      event: _dividendEvent(
        id: 'div-2',
        date: DateTime.utc(2026, 4, 18),
        amount: '144',
      ),
      assetId: 'US:SCHD',
      assetLabel: 'Schwab US Dividend Equity ETF',
      withholdingInBase: _d('36'),
      withholdingOriginal: _d('36'),
      withholdingCurrency: 'USD',
    ),
    DividendCenterEvent(
      event: _dividendEvent(
        id: 'div-3',
        date: DateTime.utc(2025, 12, 20),
        amount: '120',
      ),
      assetId: 'US:SCHD',
      assetLabel: 'Schwab US Dividend Equity ETF',
      withholdingInBase: _d('30'),
      withholdingOriginal: _d('30'),
      withholdingCurrency: 'USD',
    ),
  ];
  return DividendCenterSnapshot(
    baseCurrency: 'USD',
    yearToDateGross: _d('400'),
    ttmGross: _d('550'),
    priorYearToDateGross: _d('320'),
    ttmWithholding: _d('110'),
    events: events,
    ranking: [
      DividendHoldingRank(
        assetId: 'US:SCHD',
        assetLabel: 'Schwab US Dividend Equity ETF',
        ttmGrossInBase: _d('330'),
        withholdingInBase: _d('66'),
        portfolioShare: 0.6,
        yieldOnCost: 0.034,
      ),
      DividendHoldingRank(
        assetId: 'US:AAPL',
        assetLabel: 'Apple Inc.',
        ttmGrossInBase: _d('220'),
        withholdingInBase: _d('44'),
        portfolioShare: 0.4,
        yieldOnCost: 0.012,
      ),
    ],
    months: [
      DividendMonthGroup(
        month: DateTime.utc(2026, 5),
        events: [events[0]],
        grossInBase: _d('220'),
        withholdingInBase: _d('44'),
      ),
      DividendMonthGroup(
        month: DateTime.utc(2026, 4),
        events: [events[1]],
        grossInBase: _d('180'),
        withholdingInBase: _d('36'),
      ),
      DividendMonthGroup(
        month: DateTime.utc(2025, 12),
        events: [events[2]],
        grossInBase: _d('150'),
        withholdingInBase: _d('30'),
      ),
    ],
  );
}

ProjectedDividend _forecast() {
  return ProjectedDividend(
    assetId: 'portfolio',
    perAsset: {DateTime.utc(2026, 6, 15): _d('210')},
    total: _d('1260'),
    currency: 'USD',
    strategy: 'composite',
    confidence: DividendForecastConfidence.medium,
    strategyBreakdown: {'ttm': _d('760'), 'declared': _d('500')},
  );
}

const _testAsset = CorporateActionAsset(
  id: 'US:AAPL',
  displayName: 'Apple Inc.',
  accountId: 'brokerage-cash',
  currency: 'USD',
);

List<Lot> _lotsForAsset(CorporateActionAsset asset) {
  if (asset.id != _testAsset.id) return const [];
  return [
    Lot(
      id: 'lot-1',
      openingTransactionId: 'buy-1',
      accountId: asset.accountId,
      assetId: asset.id,
      currency: asset.currency,
      originalQuantity: _d('100'),
      remainingQuantity: _d('100'),
      costPerUnit: _d('150'),
      openedAt: DateTime.utc(2025, 1, 2),
    ),
  ];
}

List<Override> _commonOverrides(SharedPreferences prefs) {
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    cashFlowNowProvider.overrideWithValue(_goldenNow),
    recurringMaterialiseDueProvider.overrideWith((ref, now) async => 0),
  ];
}

List<Override> _cashflowOverrides(SharedPreferences prefs) => [
  ..._commonOverrides(prefs),
  cashFlowSummaryProvider.overrideWith(
    (ref, request) async => _cashFlowSummary(request.period),
  ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  runAllVariants('cashflow_page', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'cashflow_page',
      variant: variant,
      overrides: _cashflowOverrides(prefs),
      child: const CashFlowPage(),
    );
    final inflowTop = tester.getTopLeft(find.text('Inflow')).dy;
    final outflowTop = tester.getTopLeft(find.text('Outflow')).dy;
    final netTop = tester.getTopLeft(find.text('Net').first).dy;
    expect(outflowTop, closeTo(inflowTop, 0.5));
    expect(netTop, greaterThan(inflowTop));
    expect(find.text('25-06'), findsNothing);
    expect(find.text('06'), findsOneWidget);
  });

  testVisualGolden('cashflow_page — wide', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotResponsive(
      tester,
      name: 'cashflow_page_wide',
      profile: ResponsiveGoldenProfile.wide,
      overrides: _cashflowOverrides(prefs),
      child: const CashFlowPage(),
    );
    final inflowTop = tester.getTopLeft(find.text('Inflow')).dy;
    expect(tester.getTopLeft(find.text('Outflow')).dy, closeTo(inflowTop, 0.5));
    expect(
      tester.getTopLeft(find.text('Net').first).dy,
      closeTo(inflowTop, 0.5),
    );
    expect(find.text('25-06'), findsOneWidget);
  });

  runAllVariants('dividend_center', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'dividend_center',
      variant: variant,
      overrides: [
        ..._commonOverrides(prefs),
        dividendCenterNowProvider.overrideWithValue(_goldenNow),
        dividendCenterSnapshotProvider.overrideWith(
          (ref) async => _dividendSnapshot(),
        ),
        dividendForecast12mProvider.overrideWith((ref) async => _forecast()),
      ],
      child: const DividendCenterPage(),
    );
  });

  runAllVariants('corporate_action_entry', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'corporate_action_entry',
      variant: variant,
      overrides: _commonOverrides(prefs),
      child: CorporateActionEntryPage(
        assets: const [_testAsset],
        lotsForAsset: _lotsForAsset,
        onSubmit: (_) {},
        engine: CostBasisEngine(
          strategy: const FifoStrategy(),
          idGenerator: () => 'fixed-lot',
        ),
        idGenerator: () => 'fixed-tx',
        now: _goldenNow,
      ),
    );
  });
}
