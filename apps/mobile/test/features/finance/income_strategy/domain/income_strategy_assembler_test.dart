import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/income_strategy/application/income_strategy_rules.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_assembler.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_plan.dart';

void main() {
  final asOf = DateTime.utc(2026, 7, 26);

  test('accepts a custom sleeve without changing the core assembler', () {
    const custom = IncomeStrategySleeveKind('bond_ladder');
    final snapshot = const IncomeStrategyAssembler().assemble(
      baseCurrency: 'USD',
      asOf: asOf,
      converter: _converter(),
      plans: const [],
      contributions: [_contribution(custom, '10')],
      rules: const [],
    );

    expect(snapshot.underlyings.single.sleeves.keys, {custom});
    expect(snapshot.realizedIncome.value, Money(Decimal.parse('10'), 'USD'));
  });

  test('rejects duplicate module contributions for one asset', () {
    const assembler = IncomeStrategyAssembler();
    expect(
      () => assembler.assemble(
        baseCurrency: 'USD',
        asOf: asOf,
        converter: _converter(),
        plans: const [],
        contributions: [
          _contribution(IncomeStrategySleeveKind.wheel, '1'),
          _contribution(IncomeStrategySleeveKind.wheel, '2'),
        ],
        rules: const [],
      ),
      throwsStateError,
    );
  });

  test('converts a native-currency plan budget before applying rules', () {
    final result = const IncomeStrategyAssembler().assemble(
      baseCurrency: 'USD',
      asOf: asOf,
      converter: _converter(withHkd: true),
      plans: [_plan(capitalBudget: Decimal.parse('78'))],
      contributions: [_contribution(IncomeStrategySleeveKind.wheel, '20')],
      rules: kCoreIncomeStrategyRules,
    );

    final underlying = result.underlyings.single;
    expect(underlying.capitalBudget, Money(Decimal.parse('10.14'), 'USD'));
    expect(
      underlying.risks.map((risk) => risk.code),
      contains(IncomeStrategyRiskCode.capitalBudgetExceeded),
    );
  });

  test('reports missing FX instead of comparing unlike currencies', () {
    final result = const IncomeStrategyAssembler().assemble(
      baseCurrency: 'USD',
      asOf: asOf,
      converter: _converter(),
      plans: [_plan(capitalBudget: Decimal.parse('78'))],
      contributions: [_contribution(IncomeStrategySleeveKind.wheel, '20')],
      rules: const [CapitalBudgetRule()],
    );

    expect(result.underlyings.single.capitalBudget, isNull);
    expect(
      result.underlyings.single.risks.map((risk) => risk.code),
      contains(IncomeStrategyRiskCode.missingFxRate),
    );
  });
}

IncomeStrategySleeveContribution _contribution(
  IncomeStrategySleeveKind kind,
  String amount,
) {
  final value = IncomeStrategyMoneyMetric(
    value: Money(Decimal.parse(amount), 'USD'),
  );
  return IncomeStrategySleeveContribution(
    asset: const IncomeStrategyAsset(
      assetId: 'hk:0700',
      symbol: '0700',
      market: 'hk',
      currency: 'HKD',
    ),
    snapshot: IncomeStrategySleeveSnapshot(
      kind: kind,
      status: 'open',
      periodStart: DateTime.utc(2026),
      asOf: DateTime.utc(2026, 7, 26),
      realizedIncome: value,
      realizedResult: value,
      projectedCash: IncomeStrategyMoneyMetric.zero('USD'),
      exposure: IncomeStrategyExposure(capitalAtRisk: value),
      cashFlows: const [],
      risks: const [],
    ),
  );
}

IncomeStrategyPlan _plan({Decimal? capitalBudget}) => IncomeStrategyPlan(
  id: 'plan-1',
  assetId: 'hk:0700',
  symbol: '0700',
  market: 'hk',
  currency: 'HKD',
  sleeveIntents: {
    IncomeStrategySleeveKind.wheel: const IncomeStrategySleeveIntent(
      kind: IncomeStrategySleeveKind.wheel,
      enabled: true,
    ),
  },
  capitalBudget: capitalBudget,
  annualIncomeTarget: null,
  maxPositionWeight: null,
  notes: null,
  sync: SyncMeta(
    ownerUserId: 'user-1',
    updatedAt: DateTime.utc(2026),
    updatedByDevice: 'device-1',
    hlc: Hlc.zero('device-1'),
  ),
);

CurrencyConverter _converter({bool withHkd = false}) => FxRateCurrencyConverter(
  InMemoryFxRateLookup([
    if (withHkd)
      FxRate(
        base: 'HKD',
        quote: 'USD',
        date: DateTime.utc(2026, 7, 26),
        rate: Decimal.parse('0.13'),
        source: 'test',
      ),
  ]),
);
