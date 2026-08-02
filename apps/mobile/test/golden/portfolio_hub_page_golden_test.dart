import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/analytics/data/providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_event.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/realized_pnl.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/portfolio_return.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/xirr_engine.dart';
import 'package:naviwealth/features/finance/investment/ui/portfolio_hub_page.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

final _now = DateTime.utc(2026, 5, 17);

Decimal _d(String value) => Decimal.parse(value);

void _expectTextFits(WidgetTester tester, String value) {
  final finder = find.text(value);
  final text = tester.widget<Text>(finder);
  final painter = TextPainter(
    text: TextSpan(text: text.data, style: text.style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  expect(
    painter.width,
    lessThanOrEqualTo(tester.getSize(finder).width + 0.5),
    reason: 'Expected "$value" to fit without horizontal truncation.',
  );
}

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: _now,
  updatedByDevice: 'golden',
  hlc: Hlc.zero('golden'),
);

class _GoldenHoldingService implements HoldingService {
  const _GoldenHoldingService(this.lots);

  final List<Lot> lots;

  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      _holdings;

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => lots;

  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) =>
      throw UnimplementedError();

  @override
  Future<void> invalidateFrom(DateTime from) async {}
}

class _GoldenReturnService implements PortfolioReturnService {
  const _GoldenReturnService();

  @override
  Future<PortfolioReturnResult> compute({
    required DateTime from,
    required DateTime to,
  }) async {
    return PortfolioReturnResult(
      from: from,
      to: to,
      baseCurrency: 'USD',
      cashFlows: const [],
      solution: const XirrConverged(rate: 0.1834, iterations: 4),
    );
  }
}

final _accounts = [
  Account(
    id: 'ibkr',
    type: AccountCategory.broker,
    name: 'IBKR Global',
    institution: 'Interactive Brokers',
    currency: 'USD',
    sync: _meta(),
  ),
  Account(
    id: 'crypto',
    type: AccountCategory.crypto,
    name: 'Cold wallet',
    currency: 'USD',
    sync: _meta(),
  ),
];

final _assets = [
  Asset(
    id: 'us:AAPL',
    type: AssetType.stock,
    symbol: 'AAPL',
    name: 'Apple',
    currency: 'USD',
    sync: _meta(),
  ),
  Asset(
    id: 'us:VOO',
    type: AssetType.etf,
    symbol: 'VOO',
    name: 'Vanguard S&P 500 ETF',
    currency: 'USD',
    sync: _meta(),
  ),
  Asset(
    id: 'crypto:BTC',
    type: AssetType.crypto,
    symbol: 'BTC',
    name: 'Bitcoin',
    currency: 'USD',
    sync: _meta(),
  ),
];

final _holdings = {
  'us:AAPL': HoldingSnapshot(
    assetId: 'us:AAPL',
    quantity: _d('18'),
    costBasisInAssetCurrency: _d('2700'),
    marketValueInAssetCurrency: _d('3420'),
    assetCurrency: 'USD',
    costBasisInBase: _d('2700'),
    marketValueInBase: _d('3420'),
    unrealizedPnlInBase: _d('720'),
    weight: _d('0.38'),
    baseCurrency: 'USD',
    asOf: _now,
  ),
  'us:VOO': HoldingSnapshot(
    assetId: 'us:VOO',
    quantity: _d('8'),
    costBasisInAssetCurrency: _d('3200'),
    marketValueInAssetCurrency: _d('3920'),
    assetCurrency: 'USD',
    costBasisInBase: _d('3200'),
    marketValueInBase: _d('3920'),
    unrealizedPnlInBase: _d('720'),
    weight: _d('0.43'),
    baseCurrency: 'USD',
    asOf: _now,
  ),
  'crypto:BTC': HoldingSnapshot(
    assetId: 'crypto:BTC',
    quantity: _d('0.028'),
    costBasisInAssetCurrency: _d('1200'),
    marketValueInAssetCurrency: _d('1680'),
    assetCurrency: 'USD',
    costBasisInBase: _d('1200'),
    marketValueInBase: _d('1680'),
    unrealizedPnlInBase: _d('480'),
    weight: _d('0.19'),
    baseCurrency: 'USD',
    asOf: _now,
  ),
};

final _lots = [
  Lot(
    id: 'lot-aapl',
    openingTransactionId: 'tx-aapl',
    accountId: 'ibkr',
    assetId: 'us:AAPL',
    currency: 'USD',
    originalQuantity: _d('18'),
    remainingQuantity: _d('18'),
    costPerUnit: _d('150'),
    openedAt: DateTime.utc(2025, 7, 10),
  ),
  Lot(
    id: 'lot-voo',
    openingTransactionId: 'tx-voo',
    accountId: 'ibkr',
    assetId: 'us:VOO',
    currency: 'USD',
    originalQuantity: _d('8'),
    remainingQuantity: _d('8'),
    costPerUnit: _d('400'),
    openedAt: DateTime.utc(2025, 9, 3),
  ),
  Lot(
    id: 'lot-btc',
    openingTransactionId: 'tx-btc',
    accountId: 'crypto',
    assetId: 'crypto:BTC',
    currency: 'USD',
    originalQuantity: _d('0.028'),
    remainingQuantity: _d('0.028'),
    costPerUnit: _d('42857.14285714'),
    openedAt: DateTime.utc(2025, 11, 2),
  ),
];

final _realizedPnl = [
  RealizedPnL(
    id: 'realized-aapl',
    sellTransactionId: 'sell-aapl',
    lotId: 'lot-old-aapl',
    accountId: 'ibkr',
    assetId: 'us:AAPL',
    currency: 'USD',
    quantity: _d('4'),
    costBasis: _d('560'),
    proceeds: _d('720'),
    fees: _d('2'),
    realizedAt: DateTime.utc(2026, 4, 14),
    lotOpenedAt: DateTime.utc(2025, 2, 2),
  ),
];

final _dividendForecast = ProjectedDividend(
  assetId: 'portfolio',
  perAsset: {
    DateTime.utc(2026, 6, 15): _d('48'),
    DateTime.utc(2026, 9, 15): _d('48'),
  },
  total: _d('96'),
  currency: 'USD',
  strategy: 'composite',
  confidence: DividendForecastConfidence.medium,
);

final _dividendCenter = DividendCenterSnapshot(
  baseCurrency: 'USD',
  yearToDateGross: _d('38'),
  ttmGross: _d('120'),
  priorYearToDateGross: _d('24'),
  ttmWithholding: _d('4'),
  events: [
    DividendCenterEvent(
      event: CashFlowEvent(
        journalEntryId: 'div-aapl',
        date: DateTime.utc(2026, 5, 8),
        kind: CashFlowKind.dividend,
        signedAmount: _d('38'),
        originalAmount: _d('38'),
        currency: 'USD',
        accountId: 'ibkr',
        counterAccountSide: AccountSide.income,
      ),
      assetId: 'us:AAPL',
      assetLabel: 'AAPL',
      withholdingInBase: _d('4'),
      withholdingOriginal: _d('4'),
      withholdingCurrency: 'USD',
    ),
  ],
  ranking: const [],
  months: const [],
);

final _corporateActions = [
  SplitAction(
    id: 'split-aapl',
    assetId: 'us:AAPL',
    effectiveDate: DateTime.utc(2026, 4, 22),
    ratio: _d('2'),
  ),
];

List<Override> _portfolioOverrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  allAssetsStreamProvider.overrideWith((_) => Stream.value(_assets)),
  equityAssetsStreamProvider.overrideWith((_) => Stream.value(_assets)),
  accountsStreamProvider.overrideWith((_) => Stream.value(_accounts)),
  holdingsSnapshotProvider.overrideWith((_) async => _holdings),
  holdingServiceProvider.overrideWith(
    (_) async => _GoldenHoldingService(_lots),
  ),
  investmentPortfoliosProvider.overrideWith((_) => Stream.value(const [])),
  portfolioCapitalAssignmentsProvider.overrideWith(
    (_) => Stream.value(const []),
  ),
  portfolioAllocationTreeProvider.overrideWith((_) => const AsyncData(null)),
  universeRebalancePlanProvider.overrideWith((_) => null),
  portfolioReturnServiceProvider.overrideWith(
    (_) async => const _GoldenReturnService(),
  ),
  realizedPnlProvider.overrideWith((_) async => _realizedPnl),
  dividendForecast12mProvider.overrideWith((_) async => _dividendForecast),
  dividendCenterSnapshotProvider.overrideWith((_) async => _dividendCenter),
  dividendForecastDeclaredActionsProvider.overrideWith(
    (_) => _corporateActions,
  ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  runAllVariants('portfolio_hub_page', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'portfolio_hub_page',
      variant: variant,
      overrides: _portfolioOverrides(prefs),
      child: const PortfolioHubPage(),
    );
    final marketValue = tester.widget<Text>(find.text('¥9,020.00'));
    expect(marketValue.style?.color, isNotNull);
    _expectTextFits(tester, '¥7,100.00');
    _expectTextFits(tester, '+¥1,920.00');
  });

  testVisualGolden('portfolio_hub_page — wide', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotResponsive(
      tester,
      name: 'portfolio_hub_page_wide',
      profile: ResponsiveGoldenProfile.wide,
      overrides: _portfolioOverrides(prefs),
      child: const PortfolioHubPage(),
    );
    _expectTextFits(tester, '¥7,100.00');
    _expectTextFits(tester, '+¥1,920.00');
  });
}
