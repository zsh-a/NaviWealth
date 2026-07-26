import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_cash_projection.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';

import '../application/dividend_income_sleeve_adapter.dart';
import '../application/income_strategy_asset_resolver.dart';
import '../application/income_strategy_coordination_rules.dart';
import '../application/income_strategy_valuation.dart';
import '../application/leaps_income_sleeve_adapter.dart';
import '../application/wheel_income_sleeve_adapter.dart';
import '../domain/income_strategy.dart';
import '../domain/income_strategy_plan.dart';
import '../domain/income_strategy_rule.dart';
import 'income_strategy_presentation.dart';

class IncomeStrategyModuleContext {
  const IncomeStrategyModuleContext({
    required this.baseCurrency,
    required this.asOf,
    required this.converter,
    required this.assets,
    required this.plans,
  });

  final String baseCurrency;
  final DateTime asOf;
  final CurrencyConverter converter;
  final IncomeStrategyAssetResolver assets;
  final List<IncomeStrategyPlan> plans;

  IncomeStrategyValuation get valuation => IncomeStrategyValuation(
    baseCurrency: baseCurrency,
    converter: converter,
    asOf: asOf,
  );
}

class IncomeStrategyModuleResult {
  const IncomeStrategyModuleResult({
    this.contributions = const [],
    this.unassignedCashFlows = const [],
  });

  final List<IncomeStrategySleeveContribution> contributions;
  final List<IncomeStrategyCashFlow> unassignedCashFlows;
}

abstract interface class IncomeStrategyModule {
  IncomeStrategySleeveKind get id;

  IncomeStrategyModulePresentation get presentation;

  List<IncomeStrategyRule> get rules;

  /// Coordination rules that reason across a whole strategy group —
  /// including cross-underlying groups (TQQQ wheel funding a QQQ LEAPS).
  List<IncomeStrategyGroupRule> get groupRules;

  Future<IncomeStrategyModuleResult> load(
    Ref ref,
    IncomeStrategyModuleContext context,
  );
}

const kIncomeStrategyModules = <IncomeStrategyModule>[
  DividendIncomeStrategyModule(),
  WheelIncomeStrategyModule(),
  LeapsCallIncomeStrategyModule(),
];

class DividendIncomeStrategyModule implements IncomeStrategyModule {
  const DividendIncomeStrategyModule();

  @override
  IncomeStrategySleeveKind get id => IncomeStrategySleeveKind.dividends;

  @override
  IncomeStrategyModulePresentation get presentation =>
      dividendIncomeStrategyPresentation;

  @override
  List<IncomeStrategyRule> get rules => const [DividendInterruptionRule()];

  @override
  List<IncomeStrategyGroupRule> get groupRules => const [];

  @override
  Future<IncomeStrategyModuleResult> load(
    Ref ref,
    IncomeStrategyModuleContext context,
  ) async {
    final centerFuture = ref.watch(dividendCenterSnapshotProvider.future);
    final holdingsFuture = ref.watch(holdingsSnapshotProvider.future);
    final projectionsFuture = ref.watch(
      dividendCashProjection90dProvider.future,
    );
    final center = await centerFuture;
    final holdings = await holdingsFuture;
    final projections = await projectionsFuture;
    final intended = context.plans
        .where(
          (plan) =>
              plan.enabledSleeves.contains(IncomeStrategySleeveKind.dividends),
        )
        .map((plan) => plan.assetId);
    return IncomeStrategyModuleResult(
      contributions: const DividendIncomeSleeveAdapter().build(
        center: center,
        holdings: {
          for (final entry in holdings.entries)
            if (context.assets.isSecurity(entry.key)) entry.key: entry.value,
        },
        assets: context.assets,
        asOf: context.asOf,
        intendedAssetIds: intended,
      ),
      unassignedCashFlows: [
        for (var i = 0; i < projections.length; i++)
          _projectedDividendFlow(
            projections[i],
            index: i,
            baseCurrency: context.baseCurrency,
          ),
      ],
    );
  }
}

class WheelIncomeStrategyModule implements IncomeStrategyModule {
  const WheelIncomeStrategyModule();

  @override
  IncomeStrategySleeveKind get id => IncomeStrategySleeveKind.wheel;

  @override
  IncomeStrategyModulePresentation get presentation =>
      wheelIncomeStrategyPresentation;

  @override
  List<IncomeStrategyRule> get rules => const [AssignmentBudgetRule()];

  @override
  List<IncomeStrategyGroupRule> get groupRules => const [StackedDownsideRule()];

  @override
  Future<IncomeStrategyModuleResult> load(
    Ref ref,
    IncomeStrategyModuleContext context,
  ) async {
    final entries = await ref.watch(tradeJournalEntriesProvider.future);
    return IncomeStrategyModuleResult(
      contributions: const WheelIncomeSleeveAdapter().buildFromEntries(
        entries: entries,
        assets: context.assets,
        valuation: context.valuation,
      ),
    );
  }
}

class LeapsCallIncomeStrategyModule implements IncomeStrategyModule {
  const LeapsCallIncomeStrategyModule();

  @override
  IncomeStrategySleeveKind get id => IncomeStrategySleeveKind.leapsCall;

  @override
  IncomeStrategyModulePresentation get presentation =>
      leapsIncomeStrategyPresentation;

  @override
  List<IncomeStrategyRule> get rules => const [LeapsBudgetRule()];

  @override
  List<IncomeStrategyGroupRule> get groupRules => const [LeapsFundingRule()];

  @override
  Future<IncomeStrategyModuleResult> load(
    Ref ref,
    IncomeStrategyModuleContext context,
  ) async {
    final positions = await ref.watch(leapsCallPositionsProvider.future);
    return IncomeStrategyModuleResult(
      contributions: const LeapsIncomeSleeveAdapter().build(
        positions: positions,
        assets: context.assets,
        valuation: context.valuation,
      ),
    );
  }
}

IncomeStrategyCashFlow _projectedDividendFlow(
  DividendCashProjection projection, {
  required int index,
  required String baseCurrency,
}) {
  final amount = Money(projection.netAmount, baseCurrency);
  return IncomeStrategyCashFlow(
    id: 'dividend_projection:${projection.date.toIso8601String()}:$index',
    assetId: 'portfolio',
    sleeve: IncomeStrategySleeveKind.dividends,
    kind: IncomeStrategyCashFlowKind.dividend,
    state: projection.certainty == DividendCashCertainty.declared
        ? IncomeStrategyCashFlowState.declared
        : IncomeStrategyCashFlowState.estimated,
    date: projection.date,
    amount: amount,
    baseAmount: amount,
    source: IncomeStrategySourceRef(
      table: 'dividend_forecast',
      id: projection.date.toIso8601String(),
      complete: projection.hasTaxEvidence,
    ),
  );
}
