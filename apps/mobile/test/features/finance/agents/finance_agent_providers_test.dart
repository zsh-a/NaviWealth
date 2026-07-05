import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/features/finance/agents/cashflow_anomaly_review_agent.dart';
import 'package:naviwealth/features/finance/agents/fire_plan_drift_monitor_agent.dart';
import 'package:naviwealth/features/finance/agents/options_income_risk_review_agent.dart';
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/agents/weekly_wealth_review_agent.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  test(
    'latestFinanceAgentArtifactsProvider returns newest visible finance artifacts',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final artifactStore = SqliteAgentArtifactStore(db: db);
      final now = DateTime.utc(2026, 7, 5, 12);
      final agentIds = <String>[
        kWeeklyWealthReviewAgentId,
        kCashflowAnomalyReviewAgentId,
        kFirePlanDriftMonitorAgentId,
        kOptionsIncomeRiskReviewAgentId,
        kWeeklyWealthReviewAgentId,
      ];

      for (var i = 0; i < agentIds.length; i++) {
        await artifactStore.save(
          _artifact(
            id: 'finance-$i',
            agentId: agentIds[i],
            domain: 'finance',
            createdAt: now.add(Duration(minutes: i)),
          ),
        );
      }
      await artifactStore.save(
        _artifact(
          id: 'health-newer',
          agentId: 'weekly_summary',
          domain: 'health',
          createdAt: now.add(const Duration(hours: 1)),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => artifactStore,
          ),
        ],
      );
      addTearDown(container.dispose);

      final artifacts = await container.read(
        finance_agent_providers.latestFinanceAgentArtifactsProvider.future,
      );

      expect(artifacts.map((artifact) => artifact.id), [
        'finance-4',
        'finance-3',
        'finance-2',
        'finance-1',
      ]);
      expect(artifacts.map((artifact) => artifact.domain).toSet(), {'finance'});
      expect(
        artifacts.map((artifact) => artifact.agentId).toSet(),
        containsAll(<String>{
          kWeeklyWealthReviewAgentId,
          kCashflowAnomalyReviewAgentId,
          kFirePlanDriftMonitorAgentId,
          kOptionsIncomeRiskReviewAgentId,
        }),
      );
    },
  );
}

AgentArtifact _artifact({
  required String id,
  required String agentId,
  required String domain,
  required DateTime createdAt,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: 'user-1',
    agentId: agentId,
    domain: domain,
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.info,
    title: id,
    summary: id,
    createdAt: createdAt,
  );
}
