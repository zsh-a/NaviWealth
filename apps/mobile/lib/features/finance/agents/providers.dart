/// FinanceOS agent providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_presentation.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import 'cashflow_anomaly_review_agent.dart';
import 'fire_plan_drift_monitor_agent.dart';
import 'options_income_risk_review_agent.dart';
import 'weekly_wealth_review_agent.dart';

final cashflowAnomalyReviewAgentProvider = Provider<CashflowAnomalyReviewAgent>(
  (ref) => const CashflowAnomalyReviewAgent(),
);

final firePlanDriftMonitorAgentProvider = Provider<FirePlanDriftMonitorAgent>(
  (ref) => const FirePlanDriftMonitorAgent(),
);

final optionsIncomeRiskReviewAgentProvider =
    Provider<OptionsIncomeRiskReviewAgent>(
      (ref) => const OptionsIncomeRiskReviewAgent(),
    );

final weeklyWealthReviewAgentProvider = Provider<WeeklyWealthReviewAgent>(
  (ref) => const WeeklyWealthReviewAgent(),
);

final financeAgentsProvider = Provider<List<Agent>>((ref) {
  return <Agent>[
    ref.watch(weeklyWealthReviewAgentProvider),
    ref.watch(cashflowAnomalyReviewAgentProvider),
    ref.watch(firePlanDriftMonitorAgentProvider),
    ref.watch(optionsIncomeRiskReviewAgentProvider),
  ];
});

const _financeHomeResultScope = agent_providers.AgentResultScope(
  domain: DomainScope.finance,
  placement: AgentResultPlacement.domainHome,
  limit: 5,
);

final latestFinanceAgentResultsProvider =
    FutureProvider.autoDispose<agent_providers.AgentResultBundle>((ref) {
      return ref.watch(
        agent_providers
            .latestAgentResultsForPlacementProvider(_financeHomeResultScope)
            .future,
      );
    });

final latestFinanceAgentArtifactsProvider =
    FutureProvider.autoDispose<List<AgentArtifact>>((ref) async {
      final bundle = await ref.watch(latestFinanceAgentResultsProvider.future);
      return bundle.artifacts;
    });

final latestFinanceAgentRunsProvider =
    FutureProvider.autoDispose<List<AgentRunRecord>>((ref) async {
      final bundle = await ref.watch(latestFinanceAgentResultsProvider.future);
      return bundle.latestRuns;
    });

final latestFinanceAgentRunProvider =
    FutureProvider.autoDispose<AgentRunRecord?>((ref) async {
      final bundle = await ref.watch(latestFinanceAgentResultsProvider.future);
      return bundle.latestRun;
    });

final latestWeeklyWealthReviewArtifactProvider =
    FutureProvider.autoDispose<AgentArtifact?>((ref) async {
      final store = await ref.watch(
        agent_providers.agentArtifactStoreProvider.future,
      );
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final artifacts = await store.latestForAgent(
        ownerUserId: ownerUserId,
        agentId: kWeeklyWealthReviewAgentId,
        limit: 1,
      );
      return artifacts.isEmpty ? null : artifacts.single;
    });

final latestWeeklyWealthReviewRunProvider =
    FutureProvider.autoDispose<AgentRunRecord?>((ref) async {
      final store = await ref.watch(
        agent_providers.agentRunStoreProvider.future,
      );
      final ownerUserId = await ref.read(currentUserIdProvider)();
      return store.latestForAgent(
        ownerUserId: ownerUserId,
        agentId: kWeeklyWealthReviewAgentId,
      );
    });
