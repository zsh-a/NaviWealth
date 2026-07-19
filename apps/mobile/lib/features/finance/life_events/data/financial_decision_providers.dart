import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/persistence/providers.dart';
import '../../../../core/sync/mutation_context.dart';
import '../../../../core/sync/outbox_provider.dart';
import '../../fire/data/fire_providers.dart';
import '../../fire/domain/fire_projection.dart';
import '../../runway/data/money_runway_providers.dart';
import '../domain/financial_decision.dart';
import '../domain/life_event_scenario.dart';
import 'financial_decision_repository.dart';

final lifeEventBaselineProvider = Provider.autoDispose<LifeEventBaseline?>((
  ref,
) {
  final runway = ref.watch(moneyRunwayProvider).value;
  if (runway == null || !runway.hasData) return null;
  final fireView = ref.watch(fireDashboardViewProvider).value;
  int? fireMonthsToTarget;
  for (final scenario in fireView?.scenarios ?? const <FireScenario>[]) {
    if (scenario.tier == FireScenarioTier.neutral) {
      fireMonthsToTarget = scenario.monthsToTarget;
      break;
    }
  }
  final monthlyIncome =
      (runway.scheduledFlows
                  .where((flow) => flow.amount > Decimal.zero)
                  .fold(Decimal.zero, (sum, flow) => sum + flow.amount) /
              Decimal.fromInt(3))
          .toDecimal(scaleOnInfinitePrecision: 2);
  return LifeEventBaseline(
    liquidBalance: runway.startingBalance,
    monthlyIncome: monthlyIncome,
    monthlyOutflow: runway.averageMonthlyExpense,
    currency: runway.currency,
    fireMonthsToTarget: fireMonthsToTarget,
  );
});

final financialDecisionRepositoryProvider =
    FutureProvider<FinancialDecisionRepository>((ref) async {
      return FinancialDecisionRepository(
        db: await ref.watch(appDatabaseProvider.future),
        outbox: await ref.watch(outboxStoreProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

final financialDecisionsProvider =
    StreamProvider.autoDispose<List<FinancialDecision>>((ref) async* {
      final repository = await ref.watch(
        financialDecisionRepositoryProvider.future,
      );
      yield* repository.watchAll();
    });
