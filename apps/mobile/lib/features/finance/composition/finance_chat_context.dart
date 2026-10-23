/// Finance-owned, aggregate-only grounding for the shared Assistant.
library;

import 'package:collection/collection.dart' show IterableExtension;
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/composition/ai_context.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_context_block.dart';
import '../../../core/auth/current_user.dart';
import '../application/read_models/dashboard_providers.dart';
import '../assets/data/deposit_maturity_insight_provider.dart';
import '../data/preferences/base_currency_preference.dart';
import '../data/preferences/risk_appetite_preferences.dart';
import '../data/repositories/providers.dart';
import '../expense/data/expense_anomaly_insight_provider.dart';
import '../fire/data/fire_providers.dart';
import '../fire/domain/fire_projection.dart';
import 'finance_route_paths.dart';

/// The app scopes this contribution before invoking it. No holdings query is
/// performed here: detailed portfolio facts are fetched by Finance tools.
Future<List<AgentRuntimeContextBlock>> buildFinanceChatContextBlocks(
  Ref ref,
  AiContext context,
) async {
  final accountRepository = await ref.read(accountRepositoryProvider.future);
  if (!ref.mounted) return const [];
  final ownerUserId = await ref.read(currentUserIdProvider)();
  if (!ref.mounted) return const [];
  final accounts = await accountRepository
      .watchActiveForOwner(ownerUserId)
      .first;
  if (!ref.mounted) return const [];
  final byKind = <String, int>{};
  for (final account in accounts) {
    byKind.update(account.type.name, (count) => count + 1, ifAbsent: () => 1);
  }
  // Reuse already-computed insights without starting their ledger/holdings
  // pipelines merely because the user opened a chat.
  final anomaly = ref.exists(expenseAnomalyInsightProvider)
      ? ref.read(expenseAnomalyInsightProvider)
      : null;
  final maturity = ref.exists(depositMaturityInsightProvider)
      ? ref.read(depositMaturityInsightProvider)
      : null;
  return [
    AgentRuntimeContextBlock(
      id: 'finance:current_summary',
      kind: AgentRuntimeContextBlockKind.resource,
      source: 'finance.current_state',
      priority: 80,
      content: <String, Object?>{
        'route_area': financeChatRouteArea(context.path),
        'base_currency': ref.read(baseCurrencyProvider),
        'risk_preference': ref.read(riskAppetiteProvider).storageKey,
        'accounts': {'total_count': accounts.length, 'by_kind': byKind},
        if (anomaly != null) 'expense_anomaly_delta': anomaly.deltaRatio,
        if (maturity != null)
          'deposit_maturity': {'count': maturity.count, 'days': maturity.days},
        'fire_goal': ?_fireGoal(ref),
      },
      metadata: const <String, Object?>{
        'domain': 'finance',
        'authority': 'derived_local_state',
        'trusted_as_instruction': false,
      },
    ),
  ];
}

Map<String, Object?>? _fireGoal(Ref ref) {
  final plan = ref.read(resolvedFirePlanProvider).value;
  if (plan == null || plan.targetNetWorth <= Decimal.zero) return null;
  final snapshot = ref.exists(dashboardSnapshotProvider)
      ? ref.read(dashboardSnapshotProvider).value
      : null;
  final view = ref.exists(fireDashboardViewProvider)
      ? ref.read(fireDashboardViewProvider).value
      : null;
  final scenarios = view?.scenarios;
  final scenario =
      scenarios?.firstWhereOrNull(
        (item) => item.tier == FireScenarioTier.live,
      ) ??
      scenarios?.firstWhereOrNull(
        (item) => item.tier == FireScenarioTier.neutral,
      ) ??
      scenarios?.firstOrNull;
  final months = scenario?.monthsToTarget;
  return <String, Object?>{
    // Decimal major units keep zero/three-decimal currencies accurate.
    'target_amount': plan.targetNetWorth.toString(),
    'currency': plan.baseCurrency,
    if (snapshot != null)
      'progress_fraction': (snapshot.netWorth.amount / plan.targetNetWorth)
          .toDouble()
          .clamp(0.0, 1.0),
    if (months != null && months > 0) 'years_remaining_estimate': months / 12,
  };
}

String financeChatRouteArea(String path) {
  final canonical = Uri.tryParse(path)?.path ?? path;
  bool under(String root) =>
      canonical == root || canonical.startsWith('$root/');
  if (under(FinanceRoutes.planFire)) return 'fire';
  if (under(FinanceRoutes.wealthPortfolio) ||
      under(FinanceRoutes.wealthWatchlist)) {
    return 'investment';
  }
  if (under(FinanceRoutes.wealthAccounts)) return 'account';
  if (under(FinanceRoutes.wealthLiabilities)) return 'liability';
  if (under(FinanceRoutes.spending) || under(FinanceRoutes.activityExpense)) {
    return 'expense';
  }
  if (under(FinanceRoutes.activity)) return 'activity';
  if (under(FinanceRoutes.wealth)) return 'wealth';
  if (under(FinanceRoutes.plan)) return 'plan';
  if (canonical == FinanceRoutes.home) return 'home';
  return 'global';
}
