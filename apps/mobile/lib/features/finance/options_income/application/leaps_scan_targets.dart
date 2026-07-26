import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_plan.dart';

import '../domain/leaps_call_position.dart';
import 'scan_orchestrator.dart';

/// Projects LEAPS-enabled income strategy plans into buy-side scan
/// targets.
///
/// Budget = the plan's LEAPS `max_cost` minus premium already committed
/// to open LEAPS on that underlying. Funding pool = realized income
/// (wheel + dividends) across the underlying's strategy group — the same
/// pool `LeapsFundingRule` checks, so the scan card and the risk rule
/// never disagree.
List<LeapsScanTarget> buildLeapsScanTargets({
  required List<IncomeStrategyPlan> plans,
  required List<LeapsCallPosition> positions,
  PortfolioIncomeStrategySnapshot? portfolio,
}) {
  final openCostBySymbol = <String, Decimal>{};
  for (final position in positions.where((position) => position.isOpen)) {
    final symbol = position.symbol.toUpperCase();
    openCostBySymbol[symbol] =
        (openCostBySymbol[symbol] ?? Decimal.zero) + position.grossEntryCost;
  }

  final fundingByAssetId = <String, Money>{};
  for (final group
      in portfolio?.groups ?? const <IncomeStrategyGroupSnapshot>[]) {
    var pool = Money.zero(group.baseCurrency);
    for (final member in group.members) {
      for (final kind in const [
        IncomeStrategySleeveKind.dividends,
        IncomeStrategySleeveKind.wheel,
      ]) {
        final sleeve = member.sleeves[kind];
        if (sleeve != null) pool += sleeve.realizedIncome.value;
      }
    }
    for (final member in group.members) {
      fundingByAssetId[member.asset.assetId] = pool;
    }
  }

  final targets = <LeapsScanTarget>[];
  for (final plan in plans) {
    if (!plan.enabledSleeves.contains(IncomeStrategySleeveKind.leapsCall)) {
      continue;
    }
    final maxCost = plan
        .intent(IncomeStrategySleeveKind.leapsCall)
        ?.decimalValue(LeapsIncomeStrategySettings.maxCost);
    Money? budgetRemaining;
    if (maxCost != null) {
      final open = openCostBySymbol[plan.symbol.toUpperCase()] ?? Decimal.zero;
      final remaining = maxCost - open;
      budgetRemaining = Money(
        remaining < Decimal.zero ? Decimal.zero : remaining,
        plan.currency,
      );
    }
    targets.add(
      LeapsScanTarget(
        symbol: plan.symbol.toUpperCase(),
        budgetRemaining: budgetRemaining,
        groupFundingPool: fundingByAssetId[plan.assetId],
      ),
    );
  }
  targets.sort((a, b) => a.symbol.compareTo(b.symbol));
  return targets;
}
