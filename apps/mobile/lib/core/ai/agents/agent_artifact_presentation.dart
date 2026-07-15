import '../../../l10n/gen/app_localizations.dart';
import 'agent_artifact.dart';

/// Shared provenance block for domain-agent artifacts.
///
/// Domain agents still own their calculations and evidence. This helper keeps
/// the common facts — local data, device execution, and optional model
/// assistance — visually consistent across every domain.
AgentMethodology localAgentMethodology(
  AppLocalizations l10n, {
  required String sourceLabel,
  bool modelAssisted = false,
}) {
  return AgentMethodology(
    title: l10n.agentResultLocalMethodTitle,
    body: modelAssisted
        ? l10n.agentResultLocalMethodAssistedBody
        : l10n.agentResultLocalMethodDeterministicBody,
    details: <AgentMetric>[
      AgentMetric(
        label: l10n.agentResultLocalMethodSourceLabel,
        value: sourceLabel,
      ),
      AgentMetric(
        label: l10n.agentResultLocalMethodRuntimeLabel,
        value: l10n.agentResultLocalMethodRuntimeValue,
      ),
    ],
  );
}

/// Returns presentation-contract violations for a user-visible artifact.
///
/// This is intentionally strict: an agent result must explain the signal,
/// show scannable metrics, and lead back to the owning workflow. Domain tests
/// call this for emitted artifacts so a new text-only result cannot silently
/// regress the shared experience.
List<String> agentArtifactPresentationIssues(AgentArtifact artifact) {
  final issues = <String>[];
  if (artifact.metrics.isEmpty) issues.add('metrics');
  if (artifact.insights.isEmpty) issues.add('insights');
  if (artifact.insights.any((insight) => insight.id == null)) {
    issues.add('insight.id');
  }
  if (artifact.insights.any((insight) => insight.route == null)) {
    issues.add('insight.route');
  }
  if (artifact.evidence.any((evidence) => evidence.route == null)) {
    issues.add('evidence.route');
  }
  if (artifact.actions.isEmpty ||
      artifact.actions.every((action) => action.route == null)) {
    issues.add('action.route');
  }
  if (artifact.methodology == null) issues.add('methodology');
  return issues;
}
