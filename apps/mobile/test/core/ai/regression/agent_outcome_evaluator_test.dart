import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';

void main() {
  group('agent outcome evaluator', () {
    test('accepts a matching ready artifact', () {
      final failures = evaluateAgentOutcomeCase(
        regressionCase: agentOutcomeRegressionCaseById(
          'finance.cashflow_anomaly_review.ready',
        ),
        result: AgentRunResult(
          agentId: 'cashflow_anomaly_review',
          status: AgentRunStatus.completed,
          startedAt: DateTime.utc(2026, 7, 5),
          finishedAt: DateTime.utc(2026, 7, 5, 0, 0, 1),
          artifactId: 'artifact-1',
        ),
        artifact: AgentArtifact(
          id: 'artifact-1',
          ownerUserId: 'u',
          agentId: 'cashflow_anomaly_review',
          domain: 'finance',
          kind: AgentArtifactKind.alert,
          severity: AgentArtifactSeverity.warning,
          title: 'Cashflow Anomaly Review',
          summary: 'Projected monthly spending is elevated.',
          insights: const <AgentInsight>[
            AgentInsight(
              title: 'Monthly spending projection',
              body: 'Current month spending is projected higher.',
            ),
            AgentInsight(
              title: 'Detector source',
              body: 'On-device anomaly detector.',
            ),
          ],
          evidence: const <AgentEvidenceRef>[
            AgentEvidenceRef(type: 'anomaly_flag', id: 'flag-1'),
          ],
          createdAt: DateTime.utc(2026, 7, 5),
        ),
      );

      expect(failures, isEmpty);
    });

    test('reports mismatched status and artifact shape', () {
      final failures = evaluateAgentOutcomeCase(
        regressionCase: agentOutcomeRegressionCaseById(
          'finance.options_income_risk_review.ready',
        ),
        result: AgentRunResult(
          agentId: 'options_income_risk_review',
          status: AgentRunStatus.skipped,
          startedAt: DateTime.utc(2026, 7, 5),
          finishedAt: DateTime.utc(2026, 7, 5, 0, 0, 1),
        ),
        artifact: AgentArtifact(
          id: 'artifact-1',
          ownerUserId: 'u',
          agentId: 'options_income_risk_review',
          domain: 'finance',
          kind: AgentArtifactKind.review,
          severity: AgentArtifactSeverity.info,
          title: 'Options Income Risk Review',
          summary: 'Clean scan.',
          createdAt: DateTime.utc(2026, 7, 5),
        ),
      );

      expect(
        failures.map((failure) => failure.field),
        containsAll(<String>[
          'status',
          'artifact.kind',
          'artifact.severity',
          'artifact.insights',
          'artifact.evidence',
        ]),
      );
    });

    test('rejects artifacts for no-finding outcomes', () {
      final failures = evaluateAgentOutcomeCase(
        regressionCase: agentOutcomeRegressionCaseById(
          'health.weekly_summary.no_finding',
        ),
        result: AgentRunResult(
          agentId: 'weekly_summary',
          status: AgentRunStatus.skipped,
          startedAt: DateTime.utc(2026, 7, 5),
          finishedAt: DateTime.utc(2026, 7, 5, 0, 0, 1),
        ),
        artifact: AgentArtifact(
          id: 'artifact-1',
          ownerUserId: 'u',
          agentId: 'weekly_summary',
          domain: 'health',
          kind: AgentArtifactKind.review,
          severity: AgentArtifactSeverity.info,
          title: 'Weekly Summary',
          summary: 'Unexpected artifact.',
          createdAt: DateTime.utc(2026, 7, 5),
        ),
      );

      expect(failures.map((failure) => failure.field), contains('artifact'));
    });
  });
}
