import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/income_strategy/application/dividend_income_sleeve_adapter.dart';
import 'package:naviwealth/features/finance/income_strategy/application/income_strategy_asset_resolver.dart';
import 'package:naviwealth/features/finance/income_strategy/composition/income_strategy_modules.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

void main() {
  test('registered modules have unique built-in ids', () {
    final ids = kIncomeStrategyModules.map((module) => module.id).toList();

    expect(ids.toSet(), hasLength(ids.length));
    expect(
      ids,
      containsAll([
        IncomeStrategySleeveKind.dividends,
        IncomeStrategySleeveKind.wheel,
        IncomeStrategySleeveKind.leapsCall,
      ]),
    );
  });

  test('a holding alone is not classified as a dividend strategy', () {
    final holding = HoldingSnapshot(
      assetId: 'nasdaq:AAPL',
      quantity: Decimal.fromInt(10),
      costBasisInAssetCurrency: Decimal.fromInt(1000),
      marketValueInAssetCurrency: Decimal.fromInt(1200),
      assetCurrency: 'USD',
      costBasisInBase: Decimal.fromInt(1000),
      marketValueInBase: Decimal.fromInt(1200),
      unrealizedPnlInBase: Decimal.fromInt(200),
      weight: Decimal.parse('0.1'),
      baseCurrency: 'USD',
      asOf: DateTime.utc(2026, 7, 26),
    );
    final center = DividendCenterSnapshot(
      baseCurrency: 'USD',
      yearToDateGross: Decimal.zero,
      ttmGross: Decimal.zero,
      priorYearToDateGross: Decimal.zero,
      ttmWithholding: Decimal.zero,
      events: const [],
      ranking: const [],
      months: const [],
    );

    final implicit = const DividendIncomeSleeveAdapter().build(
      center: center,
      holdings: {'nasdaq:AAPL': holding},
      assets: IncomeStrategyAssetResolver(const []),
      asOf: DateTime.utc(2026, 7, 26),
    );
    final intended = const DividendIncomeSleeveAdapter().build(
      center: center,
      holdings: {'nasdaq:AAPL': holding},
      assets: IncomeStrategyAssetResolver(const []),
      asOf: DateTime.utc(2026, 7, 26),
      intendedAssetIds: const ['nasdaq:AAPL'],
    );

    expect(implicit, isEmpty);
    expect(intended.single.asset.assetId, 'nasdaq:AAPL');
  });
}
