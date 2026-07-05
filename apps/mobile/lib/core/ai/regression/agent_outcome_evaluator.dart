/// Domain-neutral evaluator for agent outcome regression cases.
///
/// The corpus stays static and feature-free. This evaluator is the executable
/// bridge that lets domain tests prove a real agent run still matches the
/// expected user-visible outcome.
library;

import '../agents/agent.dart';
import '../agents/agent_artifact.dart';
import '../agents/agent_intents.dart';
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
  final resultTraceId = _nonEmpty(result.traceId);
  final artifactTraceId = _nonEmpty(artifact.traceId);
  if (resultTraceId != artifactTraceId) {
    add('artifact.traceId', resultTraceId, artifactTraceId);
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

  final actionKinds = {for (final action in artifact.actions) action.kind};
  final missingActionKinds = regressionCase.expectedActionKinds.difference(
    actionKinds,
  );
  if (missingActionKinds.isNotEmpty) {
    add(
      'artifact.actions.kind',
      regressionCase.expectedActionKinds,
      actionKinds,
    );
  } else {
    final unexpectedActionKinds = actionKinds.difference(
      regressionCase.expectedActionKinds,
    );
    if (unexpectedActionKinds.isNotEmpty) {
      add(
        'artifact.actions.kind',
        regressionCase.expectedActionKinds,
        actionKinds,
      );
    }
  }

  final actionIntents = {
    for (final action in artifact.actions)
      if (action.intent != null) action.intent!,
  };
  final missingActionIntents = regressionCase.expectedActionIntents.difference(
    actionIntents,
  );
  if (missingActionIntents.isNotEmpty) {
    add(
      'artifact.actions.intent',
      regressionCase.expectedActionIntents,
      actionIntents,
    );
  } else {
    final unexpectedActionIntents = actionIntents.difference(
      regressionCase.expectedActionIntents,
    );
    if (unexpectedActionIntents.isNotEmpty) {
      add(
        'artifact.actions.intent',
        regressionCase.expectedActionIntents,
        actionIntents,
      );
    }
  }

  final intentActions = [
    for (final action in artifact.actions)
      if (action.intent != null) action,
  ];
  final actionObjectTypes = {
    for (final action in intentActions) action.objectType,
  };
  if (actionObjectTypes.any((type) => type != kAgentArtifactObjectType)) {
    add(
      'artifact.actions.objectType',
      kAgentArtifactObjectType,
      actionObjectTypes,
    );
  }
  final actionObjectIds = {for (final action in intentActions) action.objectId};
  if (actionObjectIds.any((id) => id != artifact.id)) {
    add('artifact.actions.objectId', artifact.id, actionObjectIds);
  }

  final missingProposals = regressionCase.expectedProposalKinds.difference(
    proposalKinds,
  );
  if (missingProposals.isNotEmpty) {
    add('proposalKinds', regressionCase.expectedProposalKinds, proposalKinds);
  } else {
    final unexpectedProposals = proposalKinds.difference(
      regressionCase.expectedProposalKinds,
    );
    if (unexpectedProposals.isNotEmpty) {
      add('proposalKinds', regressionCase.expectedProposalKinds, proposalKinds);
    }
  }

  return failures;
}

List<AgentOutcomeEvaluationFailure> evaluateAgentOutcomeCaseWithoutRun({
  required AgentOutcomeRegressionCase regressionCase,
  required String reason,
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

  if (regressionCase.expectedStatus != AgentOutcomeRegressionStatus.noFinding) {
    add('status', regressionCase.expectedStatus, 'not_run:$reason');
  }
  if (artifact != null) {
    add('artifact', null, artifact.id);
  }
  if (regressionCase.expectedProposalKinds.isNotEmpty ||
      proposalKinds.isNotEmpty) {
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

String? _nonEmpty(String? value) {
  if (value == null || value.isEmpty) return null;
  return value;
}

AgentOutcomeRegressionCase agentOutcomeRegressionCaseById(String id) {
  for (final regressionCase in agentOutcomeRegressionCorpus) {
    if (regressionCase.id == id) return regressionCase;
  }
  throw StateError('Unknown agent outcome regression case: $id');
}
