import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/data/market/providers/options/options_chain_provider.dart';
import 'package:naviwealth/features/options_income/application/scan_orchestrator.dart';
import 'package:naviwealth/features/options_income/data/options_opportunity_cache_repository.dart';
import 'package:naviwealth/features/options_income/domain/approved_underlying.dart';
import 'package:naviwealth/features/options_income/domain/option_contract.dart';
import 'package:naviwealth/features/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/options_income/domain/services/opportunity_scorer.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  late AppDatabase db;
  late OptionsOpportunityCacheRepository cache;

  setUp(() {
    db = makeTestDatabase();
    cache = OptionsOpportunityCacheRepository(db: db);
  });

  tearDown(() async {
    cache.dispose();
    await db.close();
  });

  test(
    'scan filters universe, captures symbol errors, and caches winners',
    () async {
      final chainProvider = _FakeOptionsChainProvider(
        snapshots: {
          'AAPL': _snapshot('AAPL', [_putContract('AAPL', strike: 190)]),
        },
        failures: {'FAIL': StateError('chain unavailable')},
      );
      final orchestrator = ScanOrchestrator(
        chainProvider: chainProvider,
        scorer: const OpportunityScorer(),
        cache: cache,
      );

      final result = await orchestrator.run(
        ScanInputs(
          ownerUserId: 'u1',
          profile: _profile(),
          approved: [
            _approved(symbol: 'AAPL'),
            _approved(symbol: 'MSFT', allowPut: false),
            _approved(symbol: 'FAIL'),
          ],
          holdingsBySymbol: const {
            // MSFT allows calls only, but fewer than 100 shares should keep it
            // out of the provider fetch universe.
            'MSFT': 50,
          },
          exposureBySymbol: {'AAPL': Decimal.parse('0.05')},
          availableCash: Money.parse('1000000', 'USD'),
          upcomingEarningsSymbols: const {},
          upcomingMacroEvent: false,
        ),
      );

      expect(result.universe, ['AAPL', 'FAIL']);
      expect(chainProvider.requests.map((r) => r.underlying), ['AAPL', 'FAIL']);
      expect(
        result.errors,
        containsPair('FAIL', contains('chain unavailable')),
      );
      expect(result.opportunities, hasLength(1));
      expect(result.opportunities.single.contract.underlying, 'AAPL');
      expect(result.rejected, isEmpty);

      final cached = await cache.getLatest('u1');
      expect(cached, hasLength(1));
      expect(
        cached.single.contract.optionSymbol,
        result.opportunities.single.contract.optionSymbol,
      );
      expect(cached.single.scanId, result.scanId);
    },
  );

  test(
    'scan caps near-duplicate strikes within a strategy expiration bucket',
    () async {
      final chainProvider = _FakeOptionsChainProvider(
        snapshots: {
          'AAPL': _snapshot('AAPL', [
            _putContract('AAPL', strike: 170),
            _putContract('AAPL', strike: 180),
            _putContract('AAPL', strike: 190),
          ]),
        },
      );
      final orchestrator = ScanOrchestrator(
        chainProvider: chainProvider,
        scorer: const OpportunityScorer(),
        cache: cache,
      );

      final result = await orchestrator.run(
        ScanInputs(
          ownerUserId: 'u1',
          profile: _profile(),
          approved: [_approved(symbol: 'AAPL')],
          holdingsBySymbol: const {},
          exposureBySymbol: const {},
          availableCash: Money.parse('1000000', 'USD'),
          upcomingEarningsSymbols: const {},
          upcomingMacroEvent: false,
        ),
      );

      expect(result.opportunities, hasLength(2));
      expect(
        result.opportunities.map((o) => o.contract.expiration).toSet(),
        hasLength(1),
      );
      expect(result.opportunities.map((o) => o.strategy).toSet(), {
        OptionsStrategyKind.cashSecuredPut,
      });

      final cached = await cache.getLatest('u1');
      expect(cached, hasLength(2));
    },
  );

  test(
    'scan only fetches covered-call underlyings with at least 100 shares',
    () async {
      final chainProvider = _FakeOptionsChainProvider(
        snapshots: {'AAPL': _snapshot('AAPL', const [])},
      );
      final orchestrator = ScanOrchestrator(
        chainProvider: chainProvider,
        scorer: const OpportunityScorer(),
        cache: cache,
      );

      final result = await orchestrator.run(
        ScanInputs(
          ownerUserId: 'u1',
          profile: _profile(),
          approved: [
            _approved(symbol: 'AAPL', allowPut: false),
            _approved(symbol: 'MSFT', allowPut: false),
          ],
          holdingsBySymbol: const {'AAPL': 100, 'MSFT': 99},
          exposureBySymbol: const {},
          availableCash: Money.parse('1000000', 'USD'),
          upcomingEarningsSymbols: const {},
          upcomingMacroEvent: false,
        ),
      );

      expect(result.universe, ['AAPL']);
      expect(chainProvider.requests.map((r) => r.underlying), ['AAPL']);
      expect(result.opportunities, isEmpty);
      expect(result.errors, isEmpty);
    },
  );

  test(
    'treats missing open interest data as warning, not hard filter',
    () async {
      final chainProvider = _FakeOptionsChainProvider(
        snapshots: {
          'AAPL': _snapshot('AAPL', [_putContract('AAPL', strike: 190, oi: 0)]),
        },
      );
      final orchestrator = ScanOrchestrator(
        chainProvider: chainProvider,
        scorer: const OpportunityScorer(),
        cache: cache,
      );

      final result = await orchestrator.run(
        ScanInputs(
          ownerUserId: 'u1',
          profile: _profile(),
          approved: [_approved(symbol: 'AAPL')],
          holdingsBySymbol: const {},
          exposureBySymbol: const {},
          availableCash: Money.parse('1000000', 'USD'),
          upcomingEarningsSymbols: const {},
          upcomingMacroEvent: false,
        ),
      );

      expect(result.opportunities, hasLength(1));
      expect(result.rejected, isEmpty);
      expect(
        result.warnings,
        containsPair('AAPL', contains('open interest appears unavailable')),
      );
    },
  );

  test('keeps low open interest as hard filter when OI data exists', () async {
    final chainProvider = _FakeOptionsChainProvider(
      snapshots: {
        'AAPL': _snapshot('AAPL', [
          _putContract('AAPL', strike: 190, oi: 10),
          _putContract('AAPL', strike: 180, oi: 500),
        ]),
      },
    );
    final orchestrator = ScanOrchestrator(
      chainProvider: chainProvider,
      scorer: const OpportunityScorer(),
      cache: cache,
    );

    final result = await orchestrator.run(
      ScanInputs(
        ownerUserId: 'u1',
        profile: _profile(),
        approved: [_approved(symbol: 'AAPL')],
        holdingsBySymbol: const {},
        exposureBySymbol: const {},
        availableCash: Money.parse('1000000', 'USD'),
        upcomingEarningsSymbols: const {},
        upcomingMacroEvent: false,
      ),
    );

    expect(result.opportunities, hasLength(1));
    expect(result.rejected, hasLength(1));
    expect(
      result.rejected.single.reasons,
      contains('open_interest_below_floor'),
    );
    expect(result.warnings, isEmpty);
  });
}

class _FakeOptionsChainProvider implements OptionsChainProvider {
  _FakeOptionsChainProvider({
    required this.snapshots,
    this.failures = const {},
  });

  final Map<String, OptionsChainSnapshot> snapshots;
  final Map<String, Object> failures;
  final List<OptionsChainRequest> requests = [];

  @override
  String get name => 'fake';

  @override
  Future<OptionsChainSnapshot> fetchChain(OptionsChainRequest request) async {
    requests.add(request);
    final symbol = request.underlying.toUpperCase();
    final failure = failures[symbol];
    if (failure != null) throw failure;
    final snapshot = snapshots[symbol];
    if (snapshot == null) {
      throw StateError('missing fake snapshot for $symbol');
    }
    return snapshot;
  }
}

OptionsStrategyProfile _profile() => defaultProfileForMode(
  OptionsStrategyMode.balanced,
).copyWith(riskDisclosureAckAt: DateTime.utc(2026, 5, 21));

ApprovedUnderlying _approved({
  required String symbol,
  bool allowPut = true,
  bool allowCall = true,
}) => ApprovedUnderlying(
  id: ApprovedUnderlying.idFor(market: AssetMarket.usStock, symbol: symbol),
  symbol: symbol,
  market: AssetMarket.usStock,
  allowPut: allowPut,
  allowCall: allowCall,
  maxBuyPrice: null,
  minSellPrice: null,
  notes: null,
  sync: SyncMeta(
    ownerUserId: 'u1',
    updatedAt: DateTime.utc(2026, 5, 21),
    updatedByDevice: 'dev',
    hlc: Hlc.zero('u1'),
  ),
);

OptionsChainSnapshot _snapshot(String symbol, List<OptionContract> contracts) =>
    OptionsChainSnapshot(
      underlying: symbol,
      underlyingPriceRaw: '200',
      currency: 'USD',
      contracts: contracts,
      fetchedAt: DateTime.utc(2026, 5, 21),
    );

OptionContract _putContract(
  String underlying, {
  required double strike,
  int oi = 500,
}) => _contract(
  underlying: underlying,
  type: OptionType.put,
  strike: strike,
  bid: 2.5,
  ask: 2.6,
  dte: 30,
  oi: oi,
  volume: 50,
);

OptionContract _contract({
  required String underlying,
  required OptionType type,
  required double strike,
  required double bid,
  required double ask,
  required int dte,
  required int oi,
  required int volume,
}) {
  final strikeDec = Decimal.parse(strike.toString());
  final bidDec = Decimal.parse(bid.toString());
  final askDec = Decimal.parse(ask.toString());
  final midDec = Decimal.parse(((bid + ask) / 2).toStringAsFixed(4));
  final spread = ((askDec - bidDec) / midDec).toDecimal(
    scaleOnInfinitePrecision: 6,
  );
  return OptionContract(
    underlying: underlying,
    market: AssetMarket.usStock,
    optionSymbol:
        '$underlying'
        '250620${type == OptionType.put ? "P" : "C"}'
        '${(strike * 1000).toInt().toString().padLeft(8, "0")}',
    type: type,
    expiration: DateTime.utc(2026, 6, 20),
    dte: dte,
    strike: Money(strikeDec, 'USD'),
    bid: Money(bidDec, 'USD'),
    ask: Money(askDec, 'USD'),
    mid: Money(midDec, 'USD'),
    volume: volume,
    openInterest: oi,
    impliedVolatility: Decimal.parse('0.25'),
    delta: null,
    underlyingPrice: Money.parse('200', 'USD'),
    bidAskSpreadPct: spread,
    fetchedAt: DateTime.utc(2026, 5, 21),
  );
}
