import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/income_strategy/application/income_strategy_coordination_rules.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_assembler.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_plan.dart';

/// Strategy groups: cross-underlying coordination (e.g. a TQQQ wheel
/// funding a QQQ LEAPS call) versus the implicit singleton default.
void main() {
  final asOf = DateTime.utc(2026, 7, 26);
  final converter = FxRateCurrencyConverter(InMemoryFxRateLookup(const []));

  PortfolioIncomeStrategySnapshot assemble({
    required List<IncomeStrategyPlan> plans,
    required List<IncomeStrategySleeveContribution> contributions,
  }) => const IncomeStrategyAssembler().assemble(
    baseCurrency: 'USD',
    asOf: asOf,
    converter: converter,
    plans: plans,
    contributions: contributions,
    rules: const [],
    groupRules: kBuiltInIncomeStrategyGroupRules,
  );

  test('wheel income on one underlying funds LEAPS on another', () {
    final snapshot = assemble(
      plans: [
        _plan(
          symbol: 'TQQQ',
          sleeve: IncomeStrategySleeveKind.wheel,
          groupId: 'g1',
          groupLabel: 'QQQ enhanced',
        ),
        _plan(
          symbol: 'QQQ',
          sleeve: IncomeStrategySleeveKind.leapsCall,
          groupId: 'g1',
          groupLabel: 'QQQ enhanced',
        ),
      ],
      contributions: [
        _contribution(
          symbol: 'TQQQ',
          kind: IncomeStrategySleeveKind.wheel,
          realizedIncome: '500',
        ),
        _contribution(
          symbol: 'QQQ',
          kind: IncomeStrategySleeveKind.leapsCall,
          capitalAtRisk: '400',
        ),
      ],
    );

    final group = snapshot.groups.singleWhere((group) => group.isExplicit);
    expect(group.label, 'QQQ enhanced');
    expect(group.members, hasLength(2));
    // The TQQQ wheel covers the QQQ LEAPS cost — no funding warning,
    // neither on the group nor mis-fired on the QQQ member.
    expect(
      group.risks.map((risk) => risk.code),
      isNot(contains(IncomeStrategyRiskCode.leapsCostNotCovered)),
    );
    for (final member in group.members) {
      expect(
        member.risks.map((risk) => risk.code),
        isNot(contains(IncomeStrategyRiskCode.leapsCostNotCovered)),
      );
    }
  });

  test('underfunded explicit group reports one group-scope risk', () {
    final snapshot = assemble(
      plans: [
        _plan(
          symbol: 'TQQQ',
          sleeve: IncomeStrategySleeveKind.wheel,
          groupId: 'g1',
        ),
        _plan(
          symbol: 'QQQ',
          sleeve: IncomeStrategySleeveKind.leapsCall,
          groupId: 'g1',
        ),
      ],
      contributions: [
        _contribution(
          symbol: 'TQQQ',
          kind: IncomeStrategySleeveKind.wheel,
          realizedIncome: '100',
        ),
        _contribution(
          symbol: 'QQQ',
          kind: IncomeStrategySleeveKind.leapsCall,
          capitalAtRisk: '400',
        ),
      ],
    );

    final group = snapshot.groups.singleWhere((group) => group.isExplicit);
    final finding = group.risks.singleWhere(
      (risk) => risk.code == IncomeStrategyRiskCode.leapsCostNotCovered,
    );
    expect(finding.groupId, 'g1');
    expect(finding.evidence['realized_income_ytd'], '100');
    expect(finding.evidence['open_leaps_cost'], '400');
    // Not duplicated onto the members.
    for (final member in group.members) {
      expect(
        member.risks.map((risk) => risk.code),
        isNot(contains(IncomeStrategyRiskCode.leapsCostNotCovered)),
      );
    }
    expect(snapshot.groupRisks, hasLength(1));
    expect(snapshot.activeRiskCount, 1);
  });

  test('stacked downside fires across group members', () {
    final snapshot = assemble(
      plans: [
        _plan(
          symbol: 'TQQQ',
          sleeve: IncomeStrategySleeveKind.wheel,
          groupId: 'g1',
        ),
        _plan(
          symbol: 'QQQ',
          sleeve: IncomeStrategySleeveKind.leapsCall,
          groupId: 'g1',
        ),
      ],
      contributions: [
        _contribution(
          symbol: 'TQQQ',
          kind: IncomeStrategySleeveKind.wheel,
          realizedIncome: '500',
          hasOpenShortPut: true,
        ),
        _contribution(symbol: 'QQQ', kind: IncomeStrategySleeveKind.leapsCall),
      ],
    );

    final group = snapshot.groups.singleWhere((group) => group.isExplicit);
    final finding = group.risks.singleWhere(
      (risk) => risk.code == IncomeStrategyRiskCode.stackedDownside,
    );
    expect(finding.groupId, 'g1');
    expect(finding.evidence['short_put_asset'], 'TQQQ');
    expect(finding.evidence['leaps_asset'], 'QQQ');
  });

  test('ungrouped assets keep the old per-underlying behaviour', () {
    final snapshot = assemble(
      plans: const [],
      contributions: [
        _contribution(
          symbol: 'QQQ',
          kind: IncomeStrategySleeveKind.leapsCall,
          capitalAtRisk: '400',
        ),
      ],
    );

    // Singleton group findings merge back into the member underlying.
    final underlying = snapshot.underlyings.single;
    expect(
      underlying.risks.map((risk) => risk.code),
      contains(IncomeStrategyRiskCode.leapsCostNotCovered),
    );
    final group = snapshot.groups.single;
    expect(group.isExplicit, isFalse);
    expect(group.label, 'QQQ');
    expect(group.risks, isEmpty);
    expect(snapshot.groupRisks, isEmpty);
  });
}

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 7, 26),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
);

IncomeStrategyPlan _plan({
  required String symbol,
  required IncomeStrategySleeveKind sleeve,
  String? groupId,
  String? groupLabel,
}) => IncomeStrategyPlan(
  id: 'plan-$symbol',
  assetId: 'nasdaq:$symbol',
  symbol: symbol,
  market: 'nasdaq',
  currency: 'USD',
  sleeveIntents: {
    sleeve: IncomeStrategySleeveIntent(kind: sleeve, enabled: true),
  },
  capitalBudget: null,
  annualIncomeTarget: null,
  maxPositionWeight: null,
  notes: null,
  groupId: groupId,
  groupLabel: groupLabel,
  sync: _meta(),
);

IncomeStrategySleeveContribution _contribution({
  required String symbol,
  required IncomeStrategySleeveKind kind,
  String realizedIncome = '0',
  String capitalAtRisk = '0',
  bool hasOpenShortPut = false,
}) {
  IncomeStrategyMoneyMetric metric(String amount) =>
      IncomeStrategyMoneyMetric(value: Money(Decimal.parse(amount), 'USD'));
  return IncomeStrategySleeveContribution(
    asset: IncomeStrategyAsset(
      assetId: 'nasdaq:$symbol',
      symbol: symbol,
      market: 'nasdaq',
      currency: 'USD',
    ),
    snapshot: IncomeStrategySleeveSnapshot(
      kind: kind,
      status: 'open',
      periodStart: DateTime.utc(2026),
      asOf: DateTime.utc(2026, 7, 26),
      realizedIncome: metric(realizedIncome),
      realizedResult: metric(realizedIncome),
      projectedCash: IncomeStrategyMoneyMetric.zero('USD'),
      exposure: IncomeStrategyExposure(
        capitalAtRisk: metric(capitalAtRisk),
        hasOpenShortPut: hasOpenShortPut,
      ),
      cashFlows: const [],
      risks: const [],
    ),
  );
}
