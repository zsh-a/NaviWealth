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

void main() {
  test(
    'latestFinanceAgentArtifactsProvider returns one newest artifact per finance agent',
    () async {
      final now = DateTime.utc(2026, 7, 5, 12);
      final artifactStore = _FakeArtifactStore([
        _artifact(
          id: 'weekly-old',
          agentId: kWeeklyWealthReviewAgentId,
          domain: 'finance',
          createdAt: now.add(const Duration(minutes: 1)),
        ),
        _artifact(
          id: 'cashflow-latest',
          agentId: kCashflowAnomalyReviewAgentId,
          domain: 'finance',
          createdAt: now.add(const Duration(minutes: 2)),
        ),
        _artifact(
          id: 'weekly-latest',
          agentId: kWeeklyWealthReviewAgentId,
          domain: 'finance',
          createdAt: now.add(const Duration(minutes: 3)),
        ),
        _artifact(
          id: 'options-latest',
          agentId: kOptionsIncomeRiskReviewAgentId,
          domain: 'finance',
          createdAt: now.add(const Duration(minutes: 4)),
        ),
        _artifact(
          id: 'fire-latest',
          agentId: kFirePlanDriftMonitorAgentId,
          domain: 'finance',
          createdAt: now.add(const Duration(minutes: 5)),
        ),
        _artifact(
          id: 'health-newer',
          agentId: 'weekly_summary',
          domain: 'health',
          createdAt: now.add(const Duration(hours: 1)),
        ),
      ]);

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
        'fire-latest',
        'options-latest',
        'weekly-latest',
        'cashflow-latest',
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

class _FakeArtifactStore implements AgentArtifactStore {
  _FakeArtifactStore(List<AgentArtifact> artifacts) : _artifacts = artifacts;

  final List<AgentArtifact> _artifacts;

  @override
  Future<void> save(AgentArtifact artifact) async {
    _artifacts.add(artifact);
  }

  @override
  Future<AgentArtifact?> read(String id) async {
    for (final artifact in _artifacts) {
      if (artifact.id == id) return artifact;
    }
    return null;
  }

  @override
  Future<void> dismiss({
    required String ownerUserId,
    required String id,
    required DateTime dismissedAt,
  }) async {}

  @override
  Future<void> snooze({
    required String ownerUserId,
    required String id,
    required DateTime until,
  }) async {}

  @override
  Future<List<AgentArtifact>> latestForAgent({
    required String ownerUserId,
    required String agentId,
    int limit = 10,
    DateTime? visibleAt,
  }) async {
    if (limit <= 0) return const <AgentArtifact>[];
    final at = visibleAt ?? DateTime.now().toUtc();
    final matches =
        _artifacts
            .where(
              (artifact) =>
                  artifact.ownerUserId == ownerUserId &&
                  artifact.agentId == agentId &&
                  artifact.isVisibleAt(at),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches.take(limit).toList(growable: false);
  }

  @override
  Future<List<AgentArtifact>> latestForDomain({
    required String ownerUserId,
    required String domain,
    int limit = 20,
    DateTime? visibleAt,
  }) {
    throw UnimplementedError('latestForDomain is not used by this test');
  }
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
