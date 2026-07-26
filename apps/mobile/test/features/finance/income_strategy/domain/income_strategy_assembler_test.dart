import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_assembler.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_plan.dart';

const _asset = IncomeStrategyAsset(
  assetId: 'us_stock:AAPL',
  symbol: 'AAPL',
  market: 'us_stock',
  currency: 'USD',
);

final _sync = SyncMeta(
  ownerUserId: 'user',
  updatedAt: DateTime.utc(2026, 7, 1),
  updatedByDevice: 'device',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'device'),
);

IncomeStrategySleeveContribution _sleeve(
  IncomeStrategySleeveKind kind, {
  String realized = '0',
  String capital = '0',
  Map<String, Object?> facts = const {},
}) => IncomeStrategySleeveContribution(
  asset: _asset,
  snapshot: IncomeStrategySleeveSnapshot(
    kind: kind,
    status: 'active',
    realizedResult: Decimal.parse(realized),
    projectedCash: Decimal.zero,
    capitalAtRisk: Decimal.parse(capital),
    marketValue: null,
    deltaEquivalentShares: null,
    cashFlows: const [],
    risks: const [],
    facts: facts,
  ),
);

IncomeStrategyPlan _plan({
  required Set<IncomeStrategySleeveKind> enabled,
  Decimal? maxLeapsCost,
  bool preserveDividend = true,
}) => IncomeStrategyPlan(
  assetId: _asset.assetId,
  symbol: _asset.symbol,
  market: _asset.market,
  currency: _asset.currency,
  enabledSleeves: enabled,
  capitalBudget: null,
  annualIncomeTarget: null,
  maxPositionWeight: null,
  maxLeapsCost: maxLeapsCost,
  maxAssignmentValue: null,
  preserveDividend: preserveDividend,
  allowSharesCalledAway: false,
  notes: null,
  sync: _sync,
);

void main() {
  test('combines any sleeve subset without inventing a shared lifecycle', () {
    final snapshot = const IncomeStrategyAssembler().assemble(
      baseCurrency: 'USD',
      plans: [
        _plan(
          enabled: const {
            IncomeStrategySleeveKind.dividends,
            IncomeStrategySleeveKind.leapsCall,
          },
        ),
      ],
      contributions: [
        _sleeve(IncomeStrategySleeveKind.dividends, realized: '300'),
        _sleeve(
          IncomeStrategySleeveKind.leapsCall,
          realized: '100',
          capital: '200',
        ),
      ],
    );

    final underlying = snapshot.underlyings.single;
    expect(underlying.sleeves, hasLength(2));
    expect(underlying.realizedResult, Decimal.fromInt(400));
    expect(
      underlying.sleeves.containsKey(IncomeStrategySleeveKind.wheel),
      isFalse,
    );
  });

  test('keeps live unplanned sleeves visible and flags them', () {
    final snapshot = const IncomeStrategyAssembler().assemble(
      baseCurrency: 'USD',
      plans: [
        _plan(enabled: const {IncomeStrategySleeveKind.dividends}),
      ],
      contributions: [
        _sleeve(IncomeStrategySleeveKind.dividends),
        _sleeve(IncomeStrategySleeveKind.wheel),
      ],
    );

    expect(
      snapshot.underlyings.single.risks.map((risk) => risk.code),
      contains(IncomeStrategyRiskCode.unplannedSleeve),
    );
  });

  test('coordinates dividend, Wheel and LEAPS risks across adapters', () {
    final snapshot = const IncomeStrategyAssembler().assemble(
      baseCurrency: 'USD',
      plans: [
        _plan(
          enabled: IncomeStrategySleeveKind.values.toSet(),
          maxLeapsCost: Decimal.fromInt(500),
        ),
      ],
      contributions: [
        _sleeve(IncomeStrategySleeveKind.dividends, realized: '100'),
        _sleeve(
          IncomeStrategySleeveKind.wheel,
          realized: '100',
          facts: const {
            'has_open_short_put': true,
            'has_open_covered_call': true,
          },
        ),
        _sleeve(IncomeStrategySleeveKind.leapsCall, capital: '700'),
      ],
    );

    final codes = snapshot.underlyings.single.risks
        .map((risk) => risk.code)
        .toSet();
    expect(codes, contains(IncomeStrategyRiskCode.stackedDownside));
    expect(codes, contains(IncomeStrategyRiskCode.dividendInterruption));
    expect(codes, contains(IncomeStrategyRiskCode.leapsCostNotCovered));
    expect(codes, contains(IncomeStrategyRiskCode.leapsBudgetExceeded));
  });

  test('fails fast when two adapters claim the same sleeve', () {
    expect(
      () => const IncomeStrategyAssembler().assemble(
        baseCurrency: 'USD',
        plans: const [],
        contributions: [
          _sleeve(IncomeStrategySleeveKind.dividends),
          _sleeve(IncomeStrategySleeveKind.dividends),
        ],
      ),
      throwsStateError,
    );
  });

  test('enforces total capital budget across arbitrary sleeves', () {
    final snapshot = const IncomeStrategyAssembler().assemble(
      baseCurrency: 'USD',
      plans: [
        IncomeStrategyPlan(
          assetId: 'us_stock:AAPL',
          symbol: 'AAPL',
          market: 'us_stock',
          currency: 'USD',
          enabledSleeves: {
            IncomeStrategySleeveKind.dividends,
            IncomeStrategySleeveKind.leapsCall,
          },
          capitalBudget: Decimal.fromInt(1200),
          annualIncomeTarget: Decimal.fromInt(100),
          maxPositionWeight: null,
          maxLeapsCost: null,
          maxAssignmentValue: null,
          preserveDividend: false,
          allowSharesCalledAway: true,
          notes: null,
          sync: _sync,
        ),
      ],
      contributions: [
        _sleeve(IncomeStrategySleeveKind.dividends, capital: '1000'),
        _sleeve(IncomeStrategySleeveKind.leapsCall, capital: '300'),
      ],
    );

    final underlying = snapshot.underlyings.single;
    expect(underlying.capitalBudget, Decimal.fromInt(1200));
    expect(underlying.annualIncomeTarget, Decimal.fromInt(100));
    expect(
      underlying.risks.map((risk) => risk.code),
      contains(IncomeStrategyRiskCode.capitalBudgetExceeded),
    );
  });
}
