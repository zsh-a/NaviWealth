/// Frozen policy cases for deciding whether an Agent finding deserves user
/// attention. These cases evaluate silence as a first-class correct outcome.
library;

import '../agents/agent_artifact.dart';
import '../attention/attention.dart';

class AgentPolicyRegressionCase {
  const AgentPolicyRegressionCase({
    required this.id,
    required this.severity,
    required this.confidence,
    required this.actionable,
    required this.fresh,
    required this.evidenceComplete,
    required this.novel,
    required this.suppressed,
    required this.notificationsAllowed,
    required this.recentInterruptCount,
    required this.expectedLevel,
    required this.expectedReason,
  });

  final String id;
  final AgentArtifactSeverity severity;
  final double confidence;
  final bool actionable;
  final bool fresh;
  final bool evidenceComplete;
  final bool novel;
  final bool suppressed;
  final bool notificationsAllowed;
  final int recentInterruptCount;
  final AttentionLevel expectedLevel;
  final String expectedReason;
}

const List<AgentPolicyRegressionCase> agentPolicyRegressionCorpus =
    <AgentPolicyRegressionCase>[
      AgentPolicyRegressionCase(
        id: 'policy.silent.duplicate_finding',
        severity: AgentArtifactSeverity.warning,
        confidence: 0.95,
        actionable: true,
        fresh: true,
        evidenceComplete: true,
        novel: false,
        suppressed: false,
        notificationsAllowed: true,
        recentInterruptCount: 0,
        expectedLevel: AttentionLevel.silent,
        expectedReason: 'unchanged_finding',
      ),
      AgentPolicyRegressionCase(
        id: 'policy.silent.stale_data',
        severity: AgentArtifactSeverity.warning,
        confidence: 0.95,
        actionable: true,
        fresh: false,
        evidenceComplete: true,
        novel: true,
        suppressed: false,
        notificationsAllowed: true,
        recentInterruptCount: 0,
        expectedLevel: AttentionLevel.silent,
        expectedReason: 'stale_input',
      ),
      AgentPolicyRegressionCase(
        id: 'policy.silent.missing_evidence',
        severity: AgentArtifactSeverity.warning,
        confidence: 0.95,
        actionable: true,
        fresh: true,
        evidenceComplete: false,
        novel: true,
        suppressed: false,
        notificationsAllowed: true,
        recentInterruptCount: 0,
        expectedLevel: AttentionLevel.silent,
        expectedReason: 'incomplete_evidence',
      ),
      AgentPolicyRegressionCase(
        id: 'policy.silent.low_confidence',
        severity: AgentArtifactSeverity.warning,
        confidence: 0.5,
        actionable: true,
        fresh: true,
        evidenceComplete: true,
        novel: true,
        suppressed: false,
        notificationsAllowed: true,
        recentInterruptCount: 0,
        expectedLevel: AttentionLevel.silent,
        expectedReason: 'low_confidence',
      ),
      AgentPolicyRegressionCase(
        id: 'policy.silent.user_suppressed',
        severity: AgentArtifactSeverity.warning,
        confidence: 0.95,
        actionable: true,
        fresh: true,
        evidenceComplete: true,
        novel: true,
        suppressed: true,
        notificationsAllowed: true,
        recentInterruptCount: 0,
        expectedLevel: AttentionLevel.silent,
        expectedReason: 'finding_suppressed',
      ),
      AgentPolicyRegressionCase(
        id: 'policy.surface.notifications_disabled',
        severity: AgentArtifactSeverity.warning,
        confidence: 0.95,
        actionable: true,
        fresh: true,
        evidenceComplete: true,
        novel: true,
        suppressed: false,
        notificationsAllowed: false,
        recentInterruptCount: 0,
        expectedLevel: AttentionLevel.surface,
        expectedReason: 'notifications_disabled',
      ),
      AgentPolicyRegressionCase(
        id: 'policy.surface.interrupt_budget_exhausted',
        severity: AgentArtifactSeverity.warning,
        confidence: 0.95,
        actionable: true,
        fresh: true,
        evidenceComplete: true,
        novel: true,
        suppressed: false,
        notificationsAllowed: true,
        recentInterruptCount: 3,
        expectedLevel: AttentionLevel.surface,
        expectedReason: 'interrupt_budget_exhausted',
      ),
      AgentPolicyRegressionCase(
        id: 'policy.interrupt.novel_actionable_warning',
        severity: AgentArtifactSeverity.warning,
        confidence: 0.95,
        actionable: true,
        fresh: true,
        evidenceComplete: true,
        novel: true,
        suppressed: false,
        notificationsAllowed: true,
        recentInterruptCount: 0,
        expectedLevel: AttentionLevel.interrupt,
        expectedReason: 'urgent_actionable_within_budget',
      ),
    ];

List<String> evaluateAgentPolicyRegressionCase(
  AgentPolicyRegressionCase regressionCase, {
  required DateTime at,
  AttentionArbiter arbiter = const AttentionArbiter(),
}) {
  final decision = arbiter.decide(
    ownerUserId: 'policy-corpus-owner',
    candidate: AttentionCandidate(
      id: regressionCase.id,
      agentId: 'daily_navigator',
      findingFingerprint: regressionCase.id,
      severity: regressionCase.severity,
      confidence: regressionCase.confidence,
      actionable: regressionCase.actionable,
      fresh: regressionCase.fresh,
      evidenceComplete: regressionCase.evidenceComplete,
      observedAt: at,
    ),
    context: AttentionPolicyContext(
      novel: regressionCase.novel,
      suppressed: regressionCase.suppressed,
      notificationsAllowed: regressionCase.notificationsAllowed,
      recentInterruptCount: regressionCase.recentInterruptCount,
    ),
    decidedAt: at,
  );
  return <String>[
    if (decision.level != regressionCase.expectedLevel)
      'level expected ${regressionCase.expectedLevel.name}, got '
          '${decision.level.name}',
    if (!decision.reasons.contains(regressionCase.expectedReason))
      'reason expected ${regressionCase.expectedReason}, got '
          '${decision.reasons.join(',')}',
  ];
}
