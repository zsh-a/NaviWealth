import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/holding_service.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/investment/domain/returns/portfolio_return.dart';
import 'package:naviwealth/features/investment/domain/returns/xirr_engine.dart';
import 'package:naviwealth/features/investment/presentation/portfolio_hub_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

final _now = DateTime.utc(2026, 5, 17);

Decimal _d(String value) => Decimal.parse(value);

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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  runAllVariants('portfolio_hub_page', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'portfolio_hub_page',
      variant: variant,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        allAssetsStreamProvider.overrideWith((_) => Stream.value(_assets)),
        accountsStreamProvider.overrideWith((_) => Stream.value(_accounts)),
        holdingsSnapshotProvider.overrideWith((_) async => _holdings),
        holdingServiceProvider.overrideWith(
          (_) async => _GoldenHoldingService(_lots),
        ),
        portfolioReturnServiceProvider.overrideWith(
          (_) async => const _GoldenReturnService(),
        ),
      ],
      child: const PortfolioHubPage(),
    );
  });
}
