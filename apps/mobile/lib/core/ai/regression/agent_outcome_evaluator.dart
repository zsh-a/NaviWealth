/// Domain-neutral evaluator for agent outcome regression cases.
///
/// The corpus stays static and feature-free. This evaluator is the executable
/// bridge that lets domain tests prove a real agent run still matches the
/// expected user-visible outcome.
library;

import '../agents/agent.dart';
import '../agents/agent_artifact.dart';
import 'agent_outcome_corpus.dart';

class AgentOutcomeEvaluationFailure {
  const AgentOutcomeEvaluationFailure({
    required this.field,
    required this.expected,
    required this.actual,
  });

  final String field;
  final Object? expected;
  final Object? actual;

  @override
  String toString() => '$field expected <$expected> but got <$actual>';
}

List<AgentOutcomeEvaluationFailure> evaluateAgentOutcomeCase({
  required AgentOutcomeRegressionCase regressionCase,
  required AgentRunResult result,
  AgentArtifact? artifact,
  Set<String> proposalKinds = const <String>{},
}) {
  final failures = <AgentOutcomeEvaluationFailure>[];
  void add(String field, Object? expected, Object? actual) {
    failures.add(
      AgentOutcomeEvaluationFailure(
        field: field,
        expected: expected,
        actual: actual,
      ),
    );
  }

  if (result.agentId != regressionCase.agentId) {
    add('agentId', regressionCase.agentId, result.agentId);
  }

  final actualStatus = _statusFromResult(result);
  if (actualStatus != regressionCase.expectedStatus) {
    add('status', regressionCase.expectedStatus, actualStatus);
  }

  if (regressionCase.expectedStatus != AgentOutcomeRegressionStatus.ready) {
    if (artifact != null) {
      add('artifact', null, artifact.id);
    }
    return failures;
  }

  if (artifact == null) {
    add('artifact', 'present', null);
    return failures;
  }

  if (result.artifactId == null) {
    add('result.artifactId', artifact.id, null);
  } else if (result.artifactId != artifact.id) {
    add('result.artifactId', artifact.id, result.artifactId);
  }
  if (artifact.agentId != regressionCase.agentId) {
    add('artifact.agentId', regressionCase.agentId, artifact.agentId);
  }
  if (artifact.domain != regressionCase.domain) {
    add('artifact.domain', regressionCase.domain, artifact.domain);
  }
  if (artifact.kind != regressionCase.expectedArtifactKind) {
    add('artifact.kind', regressionCase.expectedArtifactKind, artifact.kind);
  }
  if (artifact.severity != regressionCase.expectedSeverity) {
    add(
      'artifact.severity',
      regressionCase.expectedSeverity,
      artifact.severity,
    );
  }

  final insightTitles = {
    for (final insight in artifact.insights) insight.title,
  };
  final missingInsights = regressionCase.expectedTopInsightTitles.difference(
    insightTitles,
  );
  if (missingInsights.isNotEmpty) {
    add(
      'artifact.insights',
      regressionCase.expectedTopInsightTitles,
      insightTitles,
    );
  }

  final evidenceTypes = {
    for (final evidence in artifact.evidence) evidence.type,
  };
  final missingEvidence = regressionCase.expectedEvidenceTypes.difference(
    evidenceTypes,
  );
  if (missingEvidence.isNotEmpty) {
    add(
      'artifact.evidence',
      regressionCase.expectedEvidenceTypes,
      evidenceTypes,
    );
  }

  final missingProposals = regressionCase.expectedProposalKinds.difference(
    proposalKinds,
  );
  if (missingProposals.isNotEmpty) {
    add('proposalKinds', regressionCase.expectedProposalKinds, proposalKinds);
  }

  return failures;
}

AgentOutcomeRegressionStatus _statusFromResult(AgentRunResult result) {
  return switch (result.userVisibleStatus) {
    AgentRunUserVisibleStatus.ready => AgentOutcomeRegressionStatus.ready,
    AgentRunUserVisibleStatus.noFinding =>
      AgentOutcomeRegressionStatus.noFinding,
    AgentRunUserVisibleStatus.failed => AgentOutcomeRegressionStatus.failed,
  };
}

AgentOutcomeRegressionCase agentOutcomeRegressionCaseById(String id) {
  for (final regressionCase in agentOutcomeRegressionCorpus) {
    if (regressionCase.id == id) return regressionCase;
  }
  throw StateError('Unknown agent outcome regression case: $id');
}
