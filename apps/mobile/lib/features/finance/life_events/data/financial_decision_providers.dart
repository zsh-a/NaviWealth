import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../../design_system/preferences/theme_preferences.dart';
import '../../fire/data/fire_providers.dart';
import '../../fire/domain/fire_projection.dart';
import '../../runway/data/money_runway_providers.dart';
import '../domain/financial_decision.dart';
import '../domain/life_event_scenario.dart';

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

final financialDecisionsProvider =
    StateNotifierProvider<FinancialDecisionController, List<FinancialDecision>>(
      (ref) =>
          FinancialDecisionController(ref.watch(sharedPreferencesProvider)),
    );

class FinancialDecisionController
    extends StateNotifier<List<FinancialDecision>> {
  FinancialDecisionController(this._preferences) : super(_load(_preferences));

  static const _key = 'naviwealth.finance.financial_decisions.v1';
  final SharedPreferences _preferences;

  static List<FinancialDecision> _load(SharedPreferences preferences) {
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final rows = jsonDecode(raw) as List<Object?>;
      return rows
          .map(
            (row) => FinancialDecision.fromJson(
              Map<String, Object?>.from(row! as Map),
            ),
          )
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<FinancialDecision> save({
    required LifeEventTemplate template,
    required LifeEventAssumptions assumptions,
    required LifeEventOutcome outcome,
    required DateTime now,
  }) async {
    final decision = FinancialDecision(
      id: const Uuid().v4(),
      template: template,
      assumptions: assumptions,
      selectedOutcome: outcome,
      decidedAt: now,
      reviewDate: now.add(const Duration(days: 90)),
    );
    state = [decision, ...state];
    await _persist();
    return decision;
  }

  Future<void> review({
    required String id,
    required LifeEventOutcome actualOutcome,
    required DateTime now,
  }) async {
    state = [
      for (final decision in state)
        if (decision.id == id)
          FinancialDecision(
            id: decision.id,
            template: decision.template,
            assumptions: decision.assumptions,
            selectedOutcome: decision.selectedOutcome,
            decidedAt: decision.decidedAt,
            reviewDate: decision.reviewDate,
            actualOutcome: actualOutcome,
            reviewedAt: now,
          )
        else
          decision,
    ];
    await _persist();
  }

  Future<void> _persist() => _preferences.setString(
    _key,
    jsonEncode(state.map((decision) => decision.toJson()).toList()),
  );
}
