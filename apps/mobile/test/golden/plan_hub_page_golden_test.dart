import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/application/planning_hub_status.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_calculator.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/finance/ui/plan_hub_page.dart';

import '_golden_setup.dart';

final _fireView = const FireCalculator().buildView(
  goal: FireGoal(
    targetAmount: Decimal.fromInt(6000000),
    monthlyExpenses: Decimal.fromInt(18000),
    monthlySurplus: Decimal.fromInt(12000),
    inflationRate: 0.025,
  ),
  currentNetWorth: Decimal.fromInt(1850000),
  baseCurrency: 'CNY',
  start: DateTime.utc(2026, 7, 26),
);

final _status = PlanningHubStatus(
  runway: PlanningRunwayStatus.watch,
  pendingLifeEventReviews: 1,
  rebalance: PlanningRebalanceStatus.attention,
  rebalanceDriftPct: 0.068,
  budgetCount: 5,
  budgetSignal: BudgetSignal.strained,
  budgetProgress: 0.86,
  dcaPlanCount: 2,
  dcaNextDueAt: DateTime.utc(2026, 8, 1),
  dcaDue: false,
  wheelCycleCount: 2,
  wheelOpenPositionCount: 1,
  isLoading: false,
  hasError: false,
);

void main() {
  runAllVariants('plan_hub_page', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'plan_hub_page',
      variant: variant,
      overrides: [
        fireDashboardViewProvider.overrideWith(
          (_) => AsyncValue.data(_fireView),
        ),
        planningHubStatusProvider.overrideWith((_) => _status),
      ],
      child: const PlanHubPage(),
    );
  });
}
