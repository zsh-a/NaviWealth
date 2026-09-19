import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/data/event_timeline_providers.dart';
import 'package:naviwealth/features/finance/investment/domain/reporting/event_timeline.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

void main() {
  test('projects cash and stock legs from one normalized action', () {
    final events = projectCorporateActionEvents([
      MarketCorporateAction(
        id: 'eastmoney:RPT_SHAREBONUS_DET:600519:2026-01-01',
        source: 'eastmoney',
        dataset: 'RPT_SHAREBONUS_DET',
        sourceKey: '600519:2026-01-01',
        revisionHash: 'revision-1',
        identityStrength: MarketCorporateActionIdentityStrength.strong,
        symbol: '600519',
        market: AssetMarket.cnA,
        kind: MarketCorporateActionKind.distribution,
        status: MarketCorporateActionStatus.implemented,
        recordDate: DateTime.utc(2026, 6, 18),
        exDate: DateTime.utc(2026, 6, 19),
        payDate: DateTime.utc(2026, 6, 20),
        currency: 'CNY',
        cashPerShare: Decimal.parse('27.624'),
        bonusRatio: Decimal.parse('0.1'),
        capitalizationRatio: Decimal.parse('0.2'),
        totalStockDistributionRatio: Decimal.parse('0.3'),
      ),
    ]);

    expect(events, hasLength(2));
    expect(
      events.map((event) => event.kind),
      containsAll(<CorporateActionKind>[
        CorporateActionKind.cashDividend,
        CorporateActionKind.stockDistribution,
      ]),
    );
    final stock = events.singleWhere(
      (event) => event.kind == CorporateActionKind.stockDistribution,
    );
    expect(stock.stockDistributionRatio, Decimal.parse('0.3'));
    expect(stock.status, MarketCorporateActionStatus.implemented);
  });
}
