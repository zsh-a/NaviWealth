/// FinanceOS agent providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/auth/current_user.dart';
import 'cashflow_anomaly_review_agent.dart';
import 'weekly_wealth_review_agent.dart';

final cashflowAnomalyReviewAgentProvider = Provider<CashflowAnomalyReviewAgent>(
  (ref) => const CashflowAnomalyReviewAgent(),
);

final weeklyWealthReviewAgentProvider = Provider<WeeklyWealthReviewAgent>(
  (ref) => const WeeklyWealthReviewAgent(),
);

final financeAgentsProvider = Provider<List<Agent>>((ref) {
  return <Agent>[
    ref.watch(weeklyWealthReviewAgentProvider),
    ref.watch(cashflowAnomalyReviewAgentProvider),
  ];
});

final latestFinanceAgentArtifactsProvider =
    FutureProvider.autoDispose<List<AgentArtifact>>((ref) async {
      final store = await ref.watch(
        agent_providers.agentArtifactStoreProvider.future,
      );
      final ownerUserId = await ref.read(currentUserIdProvider)();
      return store.latestForDomain(
        ownerUserId: ownerUserId,
        domain: 'finance',
        limit: 3,
      );
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
