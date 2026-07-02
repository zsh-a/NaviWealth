import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset_meta.dart';
import 'package:naviwealth/features/finance/assets/ui/assets_list_models.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/manual_asset_metadata.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

void main() {
  group('buildAssetRows', () {
    test('orders manual sections and cash account groups predictably', () {
      final cashZ = _asset(
        id: 'cash-z',
        type: AssetType.cash,
        metadataJson: const CashMetadata(accountId: 'z').encode(),
      );
      final cashA = _asset(
        id: 'cash-a',
        type: AssetType.cash,
        metadataJson: const CashMetadata(accountId: 'a').encode(),
      );
      final orphanCash = _asset(id: 'orphan', type: AssetType.cash);
      final termDeposit = _asset(
        id: 'term',
        type: AssetType.bankDepositTerm,
        metadataJson: DepositMetadata(
          accountId: 'z',
          principal: Decimal.parse('1000'),
          interestRate: Decimal.parse('0.03'),
        ).encode(),
      );

      final rows = buildAssetRows(
        manual: [termDeposit, cashZ, orphanCash, cashA],
        securities: const [],
        physical: const [],
        holdings: const {},
        valuationMap: {
          cashA.id: Decimal.parse('10'),
          cashZ.id: Decimal.parse('20'),
          orphanCash.id: Decimal.parse('30'),
          termDeposit.id: Decimal.parse('1000'),
        },
        accountById: {
          'z': _account(id: 'z', name: 'Wallet'),
          'a': _account(id: 'a', name: 'Brokerage'),
        },
      );

      expect(rows[0], isA<ManualTypeHeaderRow>());
      expect((rows[0] as ManualTypeHeaderRow).type, AssetType.cash);
      expect((rows[1] as CashGroupHeaderRow).accountId, 'a');
      expect((rows[2] as ManualAssetTileRow).asset.id, cashA.id);
      expect((rows[2] as ManualAssetTileRow).value, Decimal.parse('10'));
      expect((rows[3] as CashGroupHeaderRow).accountId, 'z');
      expect((rows[4] as ManualAssetTileRow).asset.id, cashZ.id);
      expect((rows[5] as ManualAssetTileRow).asset.id, orphanCash.id);
      expect((rows[6] as GapRow).height, 12);
      expect((rows[7] as ManualTypeHeaderRow).type, AssetType.bankDepositTerm);
      expect((rows[8] as ManualAssetTileRow).asset.id, termDeposit.id);
    });

    test('uses security type order and attaches holding snapshots', () {
      final crypto = _asset(
        id: 'crypto:BTC',
        type: AssetType.crypto,
        symbol: 'BTC',
      );
      final stock = _asset(
        id: 'us_stock:AAPL',
        type: AssetType.stock,
        symbol: 'AAPL',
      );
      final stockSnapshot = _snapshot(stock.id);

      final rows = buildAssetRows(
        manual: const [],
        securities: [crypto, stock],
        physical: const [],
        holdings: {stock.id: stockSnapshot},
        valuationMap: const {},
        accountById: const {},
      );

      expect((rows[0] as SecurityTypeHeaderRow).type, AssetType.stock);
      expect((rows[1] as SecurityAssetTileRow).asset.id, stock.id);
      expect((rows[1] as SecurityAssetTileRow).snapshot, stockSnapshot);
      expect((rows[3] as SecurityTypeHeaderRow).type, AssetType.crypto);
      expect((rows[4] as SecurityAssetTileRow).asset.id, crypto.id);
      expect((rows[4] as SecurityAssetTileRow).snapshot, isNull);
    });

    test('appends physical asset section after financial asset rows', () {
      final cash = _asset(id: 'cash', type: AssetType.cash);
      final stock = _asset(
        id: 'us_stock:AAPL',
        type: AssetType.stock,
        symbol: 'AAPL',
      );
      final home = _physical(
        id: 'real_estate:home',
        type: AssetType.realEstate,
        name: 'Home',
      );
      final car = _physical(
        id: 'vehicle:car',
        type: AssetType.vehicle,
        name: 'Car',
      );

      final rows = buildAssetRows(
        manual: [cash],
        securities: [stock],
        physical: [home, car],
        holdings: const {},
        valuationMap: {cash.id: Decimal.parse('10')},
        accountById: const {},
      );

      expect(rows.map((row) => row.runtimeType), [
        ManualTypeHeaderRow,
        ManualAssetTileRow,
        GapRow,
        SecurityTypeHeaderRow,
        SecurityAssetTileRow,
        GapRow,
        PhysicalHeaderRow,
        PhysicalAssetTileRow,
        GapRow,
        PhysicalAssetTileRow,
        GapRow,
        GapRow,
      ]);
      expect((rows[7] as PhysicalAssetTileRow).asset.id, home.id);
      expect((rows[9] as PhysicalAssetTileRow).asset.id, car.id);
      expect((rows.last as GapRow).height, 12);
    });
  });

  group('orderedSecurities', () {
    test('sorts by security bucket before symbol', () {
      final assets = [
        _asset(id: 'crypto:ETH', type: AssetType.crypto, symbol: 'ETH'),
        _asset(id: 'us_stock:MSFT', type: AssetType.stock, symbol: 'MSFT'),
        _asset(id: 'us_stock:AAPL', type: AssetType.stock, symbol: 'AAPL'),
        _asset(id: 'fund:VOO', type: AssetType.etf, symbol: 'VOO'),
      ];

      expect(orderedSecurities(assets).map((a) => a.symbol), [
        'AAPL',
        'MSFT',
        'VOO',
        'ETH',
      ]);
    });
  });
}

Asset _asset({
  required String id,
  required AssetType type,
  String? symbol,
  String currency = 'USD',
  String? metadataJson,
}) => Asset(
  id: id,
  type: type,
  symbol: symbol ?? id,
  currency: currency,
  metadataJson: metadataJson,
  sync: _meta(),
);

Account _account({required String id, required String name}) => Account(
  id: id,
  type: AccountCategory.bank,
  name: name,
  currency: 'USD',
  sync: _meta(),
);

HoldingSnapshot _snapshot(String assetId) => HoldingSnapshot(
  assetId: assetId,
  quantity: Decimal.one,
  costBasisInAssetCurrency: Decimal.zero,
  marketValueInAssetCurrency: Decimal.parse('100'),
  assetCurrency: 'USD',
  costBasisInBase: Decimal.zero,
  marketValueInBase: Decimal.parse('100'),
  unrealizedPnlInBase: Decimal.zero,
  weight: Decimal.zero,
  baseCurrency: 'USD',
  asOf: DateTime.utc(2026),
);

PhysicalAsset _physical({
  required String id,
  required AssetType type,
  required String name,
}) {
  return PhysicalAsset(
    row: AssetRow(
      id: id,
      type: type,
      symbol: name,
      currency: 'USD',
      name: name,
      ownerUserId: 'u1',
      updatedAt: DateTime.utc(2026),
      updatedByDevice: 'dev',
      hlc: Hlc.zero('dev'),
    ),
    meta: PhysicalAssetMeta(
      purchaseDate: DateTime.utc(2024),
      purchasePrice: Decimal.parse('100'),
    ),
  );
}

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u1',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'dev',
  hlc: Hlc.zero('dev'),
);
