import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/options_income/data/options_opportunity_cache_repository.dart';
import 'package:naviwealth/features/finance/options_income/domain/opportunity_explanation.dart';
import 'package:naviwealth/features/finance/options_income/domain/option_contract.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_opportunity.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  late AppDatabase db;
  late OptionsOpportunityCacheRepository repo;

  setUp(() {
    db = makeTestDatabase();
    repo = OptionsOpportunityCacheRepository(db: db);
  });

  tearDown(() async {
    repo.dispose();
    await db.close();
  });

  test('replaceBatch stores one latest sorted batch per owner', () async {
    await repo.replaceBatch(
      ownerUserId: 'u1',
      scanId: 'scan-1',
      opportunities: [
        _opportunity(symbol: 'AAPL', score: '0.45', scanId: 'scan-1'),
        _opportunity(symbol: 'MSFT', score: '0.90', scanId: 'scan-1'),
      ],
    );
    await repo.replaceBatch(
      ownerUserId: 'u2',
      scanId: 'other-owner',
      opportunities: [
        _opportunity(symbol: 'NVDA', score: '0.70', scanId: 'other-owner'),
      ],
    );

    var latest = await repo.getLatest('u1');
    expect(latest.map((o) => o.contract.underlying), ['MSFT', 'AAPL']);
    expect(latest.map((o) => o.scanId).toSet(), {'scan-1'});

    var state = await repo.latestScanState('u1');
    expect(state, isNotNull);
    expect(state!.scanId, 'scan-1');
    expect(state.count, 2);

    await repo.replaceBatch(
      ownerUserId: 'u1',
      scanId: 'scan-2',
      opportunities: [
        _opportunity(symbol: 'TSLA', score: '0.60', scanId: 'scan-2'),
      ],
    );

    latest = await repo.getLatest('u1');
    expect(latest.map((o) => o.contract.underlying), ['TSLA']);
    expect(latest.single.scanId, 'scan-2');
    state = await repo.latestScanState('u1');
    expect(state!.scanId, 'scan-2');
    expect(state.count, 1);

    final otherOwner = await repo.getLatest('u2');
    expect(otherOwner.map((o) => o.contract.underlying), ['NVDA']);
  });

  test('clearForUser deletes cached rows only for that owner', () async {
    final changes = expectLater(repo.changes, emitsInOrder(['u1', 'u2', 'u1']));

    await repo.replaceBatch(
      ownerUserId: 'u1',
      scanId: 'scan-1',
      opportunities: [
        _opportunity(symbol: 'AAPL', score: '0.45', scanId: 'scan-1'),
      ],
    );
    await repo.replaceBatch(
      ownerUserId: 'u2',
      scanId: 'scan-2',
      opportunities: [
        _opportunity(symbol: 'MSFT', score: '0.55', scanId: 'scan-2'),
      ],
    );
    await repo.clearForUser('u1');

    await changes;
    expect(await repo.getLatest('u1'), isEmpty);
    expect(await repo.latestScanState('u1'), isNull);
    expect(await repo.getLatest('u2'), hasLength(1));
  });

  test(
    'getLatest round-trips contract, metrics, risk, and explanation',
    () async {
      await repo.replaceBatch(
        ownerUserId: 'u1',
        scanId: 'scan-1',
        opportunities: [
          _opportunity(symbol: 'AAPL', score: '0.45', scanId: 'scan-1'),
        ],
      );

      final latest = await repo.getLatest('u1');
      expect(latest, hasLength(1));
      final opp = latest.single;
      expect(opp.strategy, OpportunityStrategy.cashSecuredPut);
      expect(opp.contract.optionSymbol, 'AAPL250620P00190000');
      expect(opp.contract.market, AssetMarket.usStock);
      expect(opp.contract.strike, Money.parse('190', 'USD'));
      final metrics = opp.metrics as OpportunityMetrics;
      expect(metrics.premium, Money.parse('255', 'USD'));
      expect(metrics.marginOfSafety, Decimal.parse('0.0627'));
      expect(opp.risk, OpportunityRiskLevel.moderate);
      expect(opp.explanation.summary, 'AAPL put');
      expect(opp.explanation.scoreBreakdown['yield'], Decimal.parse('0.45'));
    },
  );
}

OptionsOpportunity _opportunity({
  required String symbol,
  required String score,
  required String scanId,
}) {
  final strike = Money.parse('190', 'USD');
  final bid = Money.parse('2.50', 'USD');
  final ask = Money.parse('2.60', 'USD');
  final mid = Money.parse('2.55', 'USD');
  final fetchedAt = DateTime.utc(2026, 6, 20, 12);
  final contract = OptionContract(
    underlying: symbol,
    market: AssetMarket.usStock,
    optionSymbol: '${symbol}250620P00190000',
    type: OptionType.put,
    expiration: DateTime.utc(2026, 7, 20),
    dte: 30,
    strike: strike,
    bid: bid,
    ask: ask,
    mid: mid,
    volume: 50,
    openInterest: 500,
    impliedVolatility: Decimal.parse('0.25'),
    delta: Decimal.parse('-0.20'),
    underlyingPrice: Money.parse('200', 'USD'),
    bidAskSpreadPct: Decimal.parse('0.0392'),
    fetchedAt: fetchedAt,
  );
  return OptionsOpportunity(
    strategy: OpportunityStrategy.cashSecuredPut,
    contract: contract,
    metrics: OpportunityMetrics(
      premium: Money.parse('255', 'USD'),
      cashRequired: Money.parse('19000', 'USD'),
      breakeven: Money.parse('187.45', 'USD'),
      staticReturn: Decimal.parse('0.0134'),
      annualizedYield: Decimal.parse('0.1630'),
      marginOfSafety: Decimal.parse('0.0627'),
    ),
    risk: OpportunityRiskLevel.moderate,
    explanation: OpportunityExplanation(
      summary: '$symbol put',
      whyGood: const ['yield'],
      whyRisky: const ['assignment'],
      bestFor: 'cash flow',
      avoidIf: 'no assignment',
      worstCase: 'assigned shares',
      scoreBreakdown: {'yield': Decimal.parse(score)},
    ),
    score: Decimal.parse(score),
    scannedAt: fetchedAt,
    scanId: scanId,
  );
}
