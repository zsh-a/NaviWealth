import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_corpus.dart';
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
          traceId: 'trace-1',
        ),
        artifact: _matchingCashflowArtifact(traceId: 'trace-1'),
      );

      expect(failures, isEmpty);
    });

    test('rejects evidence routed outside its registered workflow', () {
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
          traceId: 'trace-1',
        ),
        artifact: _matchingCashflowArtifact(
          traceId: 'trace-1',
          evidenceRoute: '/wealth',
        ),
      );

      expect(
        failures.map((failure) => failure.field),
        contains('artifact.evidence.anomaly_flag.route'),
      );
    });

    test('rejects emitted evidence without a route contract', () {
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
          traceId: 'trace-1',
        ),
        artifact: _matchingCashflowArtifact(
          traceId: 'trace-1',
          additionalEvidence: const <AgentEvidenceRef>[
            AgentEvidenceRef(
              type: 'unregistered_source',
              id: 'source-1',
              route: '/activity/cashflow',
            ),
          ],
        ),
      );

      expect(
        failures.map((failure) => failure.field),
        contains('artifact.evidence.unregistered_source.routeContract'),
      );
    });

    test('evidence route patterns distinguish exact and dynamic paths', () {
      expect(
        agentEvidenceRouteMatches('/activity/cashflow', '/activity/cashflow'),
        isTrue,
      );
      expect(
        agentEvidenceRouteMatches('/activity/cashflow', '/activity/cashflow/1'),
        isFalse,
      );
      expect(
        agentEvidenceRouteMatches('/wealth/assets/*', '/wealth/assets/asset-1'),
        isTrue,
      );
      expect(
        agentEvidenceRouteMatches('/wealth/assets/*', '/wealth/assets/'),
        isFalse,
      );
    });

    test('every corpus evidence type declares a valid route pattern', () {
      for (final regressionCase in agentOutcomeRegressionCorpus) {
        expect(
          regressionCase.expectedEvidenceRoutePatterns.keys,
          containsAll(regressionCase.expectedEvidenceTypes),
          reason: regressionCase.id,
        );
        for (final pattern
            in regressionCase.expectedEvidenceRoutePatterns.values) {
          expect(pattern, startsWith('/'), reason: regressionCase.id);
          expect(
            pattern.substring(0, pattern.length - 1),
            isNot(contains('*')),
            reason: regressionCase.id,
          );
        }
      }
    });

    test('validates direct route actions', () {
      const regressionCase = AgentOutcomeRegressionCase(
        id: 'finance.route.ready',
        agentId: 'route_agent',
        domain: 'finance',
        snapshotId: 'finance.route.fixture',
        expectedStatus: AgentOutcomeRegressionStatus.ready,
        expectedArtifactKind: AgentArtifactKind.review,
        expectedSeverity: AgentArtifactSeverity.info,
        expectedActionKinds: <String>{'open_route'},
        expectedActionRoutes: <String>{'/plan/fire'},
      );
      final result = AgentRunResult(
        agentId: 'route_agent',
        status: AgentRunStatus.completed,
        startedAt: DateTime.utc(2026, 7, 5),
        finishedAt: DateTime.utc(2026, 7, 5, 0, 0, 1),
        artifactId: 'artifact-1',
      );

      AgentArtifact artifact(String route) => AgentArtifact(
        id: 'artifact-1',
        ownerUserId: 'u',
        agentId: 'route_agent',
        domain: 'finance',
        kind: AgentArtifactKind.review,
        severity: AgentArtifactSeverity.info,
        title: 'Route result',
        summary: 'Open the related plan.',
        metrics: const <AgentMetric>[
          AgentMetric(label: 'Status', value: 'Ready'),
        ],
        insights: <AgentInsight>[
          AgentInsight(
            id: 'route-result',
            title: 'Related plan',
            body: 'Open the related plan.',
            route: route,
          ),
        ],
        actions: <AgentAction>[
          AgentAction(kind: 'open_route', label: 'Open plan', route: route),
        ],
        methodology: const AgentMethodology(
          title: 'Method',
          body: 'Deterministic test fixture.',
        ),
        createdAt: DateTime.utc(2026, 7, 5),
      );

      expect(
        evaluateAgentOutcomeCase(
          regressionCase: regressionCase,
          result: result,
          artifact: artifact('/plan/fire'),
        ),
        isEmpty,
      );
      expect(
        evaluateAgentOutcomeCase(
          regressionCase: regressionCase,
          result: result,
          artifact: artifact('/plan/budget'),
        ).map((failure) => failure.field),
        ['artifact.actions.route'],
      );
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
          traceId: 'trace-1',
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
          traceId: 'trace-1',
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
          'artifact.actions.kind',
          'artifact.actions.intent',
        ]),
      );
    });

    test('rejects unexpected proposal kinds for follow-up-only outcomes', () {
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
          traceId: 'trace-1',
        ),
        artifact: _matchingCashflowArtifact(traceId: 'trace-1'),
        proposalKinds: const <String>{'journal_entry'},
      );

      expect(failures.map((failure) => failure.field), ['proposalKinds']);
    });

    test('rejects unexpected artifact actions', () {
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
          traceId: 'trace-1',
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
          actions: const <AgentAction>[
            AgentAction(
              kind: 'review',
              label: 'Ask',
              intent: 'agent.explainResult',
              objectType: kAgentArtifactObjectType,
              objectId: 'artifact-1',
            ),
            AgentAction(
              kind: 'apply_proposal',
              label: 'Apply',
              intent: 'finance.createTransaction',
              objectType: kAgentArtifactObjectType,
              objectId: 'artifact-1',
            ),
          ],
          traceId: 'trace-1',
          createdAt: DateTime.utc(2026, 7, 5),
        ),
      );

      expect(
        failures.map((failure) => failure.field),
        containsAll(<String>[
          'artifact.actions.kind',
          'artifact.actions.intent',
        ]),
      );
    });

    test('rejects intent actions that target the wrong object', () {
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
        artifact: _matchingCashflowArtifact(
          traceId: null,
          actionObjectType: 'finance_transaction',
          actionObjectId: 'other-object',
        ),
      );

      expect(
        failures.map((failure) => failure.field),
        containsAll(<String>[
          'artifact.actions.objectType',
          'artifact.actions.objectId',
        ]),
      );
    });

    test(
      'requires ready result and artifact trace ids to match when present',
      () {
        final noTraceFailures = evaluateAgentOutcomeCase(
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
          artifact: _matchingCashflowArtifact(traceId: null),
        );

        expect(noTraceFailures, isEmpty);

        final oneSidedTraceFailures = evaluateAgentOutcomeCase(
          regressionCase: agentOutcomeRegressionCaseById(
            'finance.cashflow_anomaly_review.ready',
          ),
          result: AgentRunResult(
            agentId: 'cashflow_anomaly_review',
            status: AgentRunStatus.completed,
            startedAt: DateTime.utc(2026, 7, 5),
            finishedAt: DateTime.utc(2026, 7, 5, 0, 0, 1),
            artifactId: 'artifact-1',
            traceId: 'trace-run',
          ),
          artifact: _matchingCashflowArtifact(traceId: null),
        );

        expect(
          oneSidedTraceFailures.map((failure) => failure.field),
          contains('artifact.traceId'),
        );

        final mismatchedTraceFailures = evaluateAgentOutcomeCase(
          regressionCase: agentOutcomeRegressionCaseById(
            'finance.cashflow_anomaly_review.ready',
          ),
          result: AgentRunResult(
            agentId: 'cashflow_anomaly_review',
            status: AgentRunStatus.completed,
            startedAt: DateTime.utc(2026, 7, 5),
            finishedAt: DateTime.utc(2026, 7, 5, 0, 0, 1),
            artifactId: 'artifact-1',
            traceId: 'trace-run',
          ),
          artifact: _matchingCashflowArtifact(traceId: 'trace-artifact'),
        );

        expect(
          mismatchedTraceFailures.map((failure) => failure.field),
          contains('artifact.traceId'),
        );
      },
    );

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

    test('accepts domain opt-out no-run outcomes', () {
      final failures = evaluateAgentOutcomeCaseWithoutRun(
        regressionCase: agentOutcomeRegressionCaseById(
          'knowledge.routine_due.domain_opt_out',
        ),
        reason: 'domain_not_enabled',
      );

      expect(failures, isEmpty);
    });

    test('rejects no-run outcomes for ready cases', () {
      final failures = evaluateAgentOutcomeCaseWithoutRun(
        regressionCase: agentOutcomeRegressionCaseById(
          'finance.weekly_wealth_review.ready',
        ),
        reason: 'domain_not_enabled',
      );

      expect(failures.map((failure) => failure.field), contains('status'));
    });
  });
}

AgentArtifact _matchingCashflowArtifact({
  required String? traceId,
  String? actionObjectType = kAgentArtifactObjectType,
  String? actionObjectId = 'artifact-1',
  String evidenceRoute = '/activity/cashflow',
  List<AgentEvidenceRef> additionalEvidence = const <AgentEvidenceRef>[],
}) {
  return AgentArtifact(
    id: 'artifact-1',
    ownerUserId: 'u',
    agentId: 'cashflow_anomaly_review',
    domain: 'finance',
    kind: AgentArtifactKind.alert,
    severity: AgentArtifactSeverity.warning,
    title: 'Cashflow Anomaly Review',
    summary: 'Projected monthly spending is elevated.',
    metrics: const <AgentMetric>[
      AgentMetric(label: 'Projected spend', value: 'Elevated'),
    ],
    insights: const <AgentInsight>[
      AgentInsight(
        id: 'monthly-spending-projection',
        title: 'Monthly spending projection',
        body: 'Current month spending is projected higher.',
        route: '/activity/cashflow',
      ),
      AgentInsight(
        id: 'detector-source',
        title: 'Detector source',
        body: 'On-device anomaly detector.',
        route: '/activity/cashflow',
      ),
    ],
    evidence: <AgentEvidenceRef>[
      AgentEvidenceRef(
        type: 'anomaly_flag',
        id: 'flag-1',
        route: evidenceRoute,
      ),
      ...additionalEvidence,
    ],
    actions: <AgentAction>[
      AgentAction(
        kind: 'review',
        label: 'Ask',
        route: '/activity/cashflow',
        intent: 'agent.explainResult',
        objectType: actionObjectType,
        objectId: actionObjectId,
      ),
    ],
    methodology: const AgentMethodology(
      title: 'Method',
      body: 'Deterministic anomaly fixture.',
    ),
    traceId: traceId,
    createdAt: DateTime.utc(2026, 7, 5),
  );
}
