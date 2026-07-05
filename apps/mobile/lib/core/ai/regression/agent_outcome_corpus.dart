/// Frozen expected outcomes for deterministic agent-result regressions.
///
/// This corpus is intentionally static: it describes the expected user-visible
/// shape for fixed snapshots without running LLM calls. Domain agent tests own
/// the executable fixtures; this file keeps the cross-domain coverage contract
/// visible in one place so new agents and failure modes do not drift out of the
/// evaluation surface.
library;

import '../agents/agent_artifact.dart';
import '../agents/agent_intents.dart';

enum AgentOutcomeRegressionStatus { ready, noFinding, failed }

class AgentOutcomeRegressionCase {
  const AgentOutcomeRegressionCase({
    required this.id,
    required this.agentId,
    required this.domain,
    required this.snapshotId,
    required this.expectedStatus,
    this.expectedArtifactKind,
    this.expectedSeverity,
    this.expectedTopInsightTitles = const <String>{},
    this.expectedEvidenceTypes = const <String>{},
    this.expectedActionKinds = const <String>{},
    this.expectedActionIntents = const <String>{},
    this.expectedProposalKinds = const <String>{},
    this.tags = const <String>{},
  });

  /// Stable identifier for failure reports.
  final String id;

  /// Stable production [Agent.id]. Kept as a string to avoid importing
  /// domain-specific feature modules into core.
  final String agentId;

  /// Domain pack id: finance / health / knowledge / execution.
  final String domain;

  /// Fixture key owned by the executable domain test. The corpus does not
  /// define the rows themselves; it defines the expected visible outcome.
  final String snapshotId;

  final AgentOutcomeRegressionStatus expectedStatus;
  final AgentArtifactKind? expectedArtifactKind;
  final AgentArtifactSeverity? expectedSeverity;
  final Set<String> expectedTopInsightTitles;
  final Set<String> expectedEvidenceTypes;
  final Set<String> expectedActionKinds;
  final Set<String> expectedActionIntents;

  /// Proposal kinds expected to be created or referenced by the outcome.
  /// Empty means the agent should not emit a proposal in this fixture.
  final Set<String> expectedProposalKinds;

  /// Auditable subsets for required eval categories such as prompt injection
  /// and missing LLM profile.
  final Set<String> tags;
}

const String kAgentOutcomeToolFailureTag = 'tool_failure';
const String kAgentOutcomeBudgetExhaustedTag = 'budget_exhausted';
const String kAgentOutcomeNoLlmProfileTag = 'no_llm_profile';
const String kAgentOutcomePromptInjectionTag = 'prompt_injection';
const String kAgentOutcomeDomainOptOutTag = 'domain_opt_out';

const List<AgentOutcomeRegressionCase>
agentOutcomeRegressionCorpus = <AgentOutcomeRegressionCase>[
  AgentOutcomeRegressionCase(
    id: 'finance.weekly_wealth_review.ready',
    agentId: 'weekly_wealth_review',
    domain: 'finance',
    snapshotId: 'finance.weekly_wealth_review.baseline_portfolio',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.review,
    expectedSeverity: AgentArtifactSeverity.warning,
    expectedTopInsightTitles: <String>{'Net worth', 'Largest allocation'},
    expectedEvidenceTypes: <String>{'finance_holding'},
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kFinanceReviewWealthIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'finance.weekly_wealth_review.no_llm_profile_fallback',
    agentId: 'weekly_wealth_review',
    domain: 'finance',
    snapshotId: 'finance.weekly_wealth_review.no_llm_profile',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.review,
    expectedSeverity: AgentArtifactSeverity.warning,
    expectedTopInsightTitles: <String>{'Net worth', 'Largest allocation'},
    expectedEvidenceTypes: <String>{'finance_holding'},
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kFinanceReviewWealthIntent},
    tags: <String>{kAgentOutcomeNoLlmProfileTag},
  ),
  AgentOutcomeRegressionCase(
    id: 'finance.cashflow_anomaly_review.ready',
    agentId: 'cashflow_anomaly_review',
    domain: 'finance',
    snapshotId: 'finance.cashflow_anomaly_review.monthly_spike',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.alert,
    expectedSeverity: AgentArtifactSeverity.warning,
    expectedTopInsightTitles: <String>{
      'Monthly spending projection',
      'Detector source',
    },
    expectedEvidenceTypes: <String>{'anomaly_flag'},
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kAgentExplainResultIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'finance.cashflow_anomaly_review.no_llm_profile_fallback',
    agentId: 'cashflow_anomaly_review',
    domain: 'finance',
    snapshotId: 'finance.cashflow_anomaly_review.no_llm_profile',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.alert,
    expectedSeverity: AgentArtifactSeverity.warning,
    expectedTopInsightTitles: <String>{
      'Monthly spending projection',
      'Detector source',
    },
    expectedEvidenceTypes: <String>{'anomaly_flag'},
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kAgentExplainResultIntent},
    tags: <String>{kAgentOutcomeNoLlmProfileTag},
  ),
  AgentOutcomeRegressionCase(
    id: 'finance.fire_plan_drift_monitor.ready',
    agentId: 'fire_plan_drift_monitor',
    domain: 'finance',
    snapshotId: 'finance.fire_plan_drift_monitor.withdrawal_rate_drift',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.review,
    expectedSeverity: AgentArtifactSeverity.warning,
    expectedTopInsightTitles: <String>{
      'Withdrawal rate above safe rate',
      'Plan snapshot',
    },
    expectedEvidenceTypes: <String>{'fire_review', 'fire_finding'},
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kAgentExplainResultIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'finance.fire_plan_drift_monitor.no_llm_profile_fallback',
    agentId: 'fire_plan_drift_monitor',
    domain: 'finance',
    snapshotId: 'finance.fire_plan_drift_monitor.no_llm_profile',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.review,
    expectedSeverity: AgentArtifactSeverity.warning,
    expectedTopInsightTitles: <String>{
      'Withdrawal rate above safe rate',
      'Plan snapshot',
    },
    expectedEvidenceTypes: <String>{'fire_review', 'fire_finding'},
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kAgentExplainResultIntent},
    tags: <String>{kAgentOutcomeNoLlmProfileTag},
  ),
  AgentOutcomeRegressionCase(
    id: 'finance.options_income_risk_review.ready',
    agentId: 'options_income_risk_review',
    domain: 'finance',
    snapshotId: 'finance.options_income_risk_review.stale_elevated_scan',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.alert,
    expectedSeverity: AgentArtifactSeverity.warning,
    expectedTopInsightTitles: <String>{
      'Scan data is stale',
      'Elevated-risk contracts present',
      'Quote quality needs review',
    },
    expectedEvidenceTypes: <String>{
      'options_income_scan',
      'options_opportunity',
    },
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kAgentExplainResultIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'finance.options_income_risk_review.no_llm_profile_fallback',
    agentId: 'options_income_risk_review',
    domain: 'finance',
    snapshotId: 'finance.options_income_risk_review.no_llm_profile',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.alert,
    expectedSeverity: AgentArtifactSeverity.warning,
    expectedTopInsightTitles: <String>{
      'Scan data is stale',
      'Elevated-risk contracts present',
      'Quote quality needs review',
    },
    expectedEvidenceTypes: <String>{
      'options_income_scan',
      'options_opportunity',
    },
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kAgentExplainResultIntent},
    tags: <String>{kAgentOutcomeNoLlmProfileTag},
  ),
  AgentOutcomeRegressionCase(
    id: 'health.morning_briefing.ready',
    agentId: 'morning_briefing',
    domain: 'health',
    snapshotId: 'health.morning_briefing.recovery_attention',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.briefing,
    expectedSeverity: AgentArtifactSeverity.attention,
    expectedTopInsightTitles: <String>{'Sleep', 'HRV', 'Finance'},
    expectedEvidenceTypes: <String>{'health_event', 'finance_event'},
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kAgentExplainResultIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'health.recovery_alert.ready',
    agentId: 'recovery_alert',
    domain: 'health',
    snapshotId: 'health.recovery_alert.hrv_decline',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.alert,
    expectedSeverity: AgentArtifactSeverity.warning,
    expectedTopInsightTitles: <String>{'HRV decline'},
    expectedEvidenceTypes: <String>{'health_metric_trend'},
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kHealthExplainRecoveryAlertIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'health.weekly_summary.no_finding',
    agentId: 'weekly_summary',
    domain: 'health',
    snapshotId: 'health.weekly_summary.empty_week',
    expectedStatus: AgentOutcomeRegressionStatus.noFinding,
  ),
  AgentOutcomeRegressionCase(
    id: 'health.weekly_summary.ready',
    agentId: 'weekly_summary',
    domain: 'health',
    snapshotId: 'health.weekly_summary.active_week',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.review,
    expectedSeverity: AgentArtifactSeverity.info,
    expectedTopInsightTitles: <String>{
      'Recovery',
      'Sleep',
      'Activity',
      'Workouts',
    },
    expectedEvidenceTypes: <String>{'health_week'},
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kAgentExplainResultIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'knowledge.assumption.ready',
    agentId: 'knowledge_assumption',
    domain: 'knowledge',
    snapshotId: 'knowledge.assumption.stale_assumption',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.review,
    expectedSeverity: AgentArtifactSeverity.attention,
    expectedTopInsightTitles: <String>{'Stale assumptions'},
    expectedEvidenceTypes: <String>{'knowledge_assumption'},
    expectedActionKinds: <String>{'open_object'},
    expectedActionIntents: <String>{kKnowledgeReviewDueItemsIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'knowledge.inbox_triage.ready',
    agentId: 'knowledge_inbox_triage',
    domain: 'knowledge',
    snapshotId: 'knowledge.inbox_triage.decision_candidate',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.review,
    expectedSeverity: AgentArtifactSeverity.info,
    expectedTopInsightTitles: <String>{'New suggestions', 'Classification'},
    expectedEvidenceTypes: <String>{'knowledge_note'},
    expectedActionKinds: <String>{'open_object'},
    expectedActionIntents: <String>{kKnowledgeReviewDueItemsIntent},
    expectedProposalKinds: <String>{'classification'},
    tags: <String>{kAgentOutcomeNoLlmProfileTag},
  ),
  AgentOutcomeRegressionCase(
    id: 'knowledge.contradiction.ready',
    agentId: 'knowledge_contradiction',
    domain: 'knowledge',
    snapshotId: 'knowledge.contradiction.invalidated_assumption',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.alert,
    expectedSeverity: AgentArtifactSeverity.warning,
    expectedTopInsightTitles: <String>{'Invalidated assumptions'},
    expectedEvidenceTypes: <String>{'knowledge_decision'},
    expectedActionKinds: <String>{'open_object'},
    expectedActionIntents: <String>{kKnowledgeReviewDueItemsIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'knowledge.contradiction.prompt_injection_guard',
    agentId: 'knowledge_contradiction',
    domain: 'knowledge',
    snapshotId: 'knowledge.contradiction.injected_memory',
    expectedStatus: AgentOutcomeRegressionStatus.noFinding,
    tags: <String>{kAgentOutcomePromptInjectionTag},
  ),
  AgentOutcomeRegressionCase(
    id: 'knowledge.review.ready',
    agentId: 'knowledge_review',
    domain: 'knowledge',
    snapshotId: 'knowledge.review.due_decision_and_stale_assumption',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.review,
    expectedSeverity: AgentArtifactSeverity.attention,
    expectedTopInsightTitles: <String>{'Decisions due', 'Stale assumptions'},
    expectedEvidenceTypes: <String>{
      'knowledge_decision',
      'knowledge_assumption',
    },
    expectedActionKinds: <String>{'open_object'},
    expectedActionIntents: <String>{kKnowledgeReviewDueItemsIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'knowledge.review.tool_failure_fallback',
    agentId: 'knowledge_review',
    domain: 'knowledge',
    snapshotId: 'knowledge.review.effect_plan_decode_failure',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.review,
    expectedSeverity: AgentArtifactSeverity.attention,
    expectedTopInsightTitles: <String>{'Decisions due', 'Stale assumptions'},
    expectedEvidenceTypes: <String>{
      'knowledge_decision',
      'knowledge_assumption',
    },
    expectedActionKinds: <String>{'open_object'},
    expectedActionIntents: <String>{kKnowledgeReviewDueItemsIntent},
    tags: <String>{kAgentOutcomeToolFailureTag},
  ),
  AgentOutcomeRegressionCase(
    id: 'execution.review.ready',
    agentId: 'execution_review',
    domain: 'execution',
    snapshotId: 'execution.review.blocked_due_work',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.review,
    expectedSeverity: AgentArtifactSeverity.attention,
    expectedTopInsightTitles: <String>{
      'Today focus',
      'Blocked work',
      'Due work',
    },
    expectedEvidenceTypes: <String>{'execution_action'},
    expectedActionKinds: <String>{'review'},
    expectedActionIntents: <String>{kAgentExplainResultIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'execution.review.budget_exhausted',
    agentId: 'execution_review',
    domain: 'execution',
    snapshotId: 'execution.review.effect_budget_exhausted',
    expectedStatus: AgentOutcomeRegressionStatus.failed,
    tags: <String>{kAgentOutcomeBudgetExhaustedTag},
  ),
  AgentOutcomeRegressionCase(
    id: 'knowledge.routine_due.ready',
    agentId: 'knowledge_routine_due',
    domain: 'knowledge',
    snapshotId: 'knowledge.routine_due.overdue_and_upcoming',
    expectedStatus: AgentOutcomeRegressionStatus.ready,
    expectedArtifactKind: AgentArtifactKind.reminder,
    expectedSeverity: AgentArtifactSeverity.attention,
    expectedTopInsightTitles: <String>{'Overdue routines', 'Upcoming routines'},
    expectedEvidenceTypes: <String>{'knowledge_routine'},
    expectedActionKinds: <String>{'open_object'},
    expectedActionIntents: <String>{kKnowledgeReviewDueItemsIntent},
  ),
  AgentOutcomeRegressionCase(
    id: 'knowledge.routine_due.domain_opt_out',
    agentId: 'knowledge_routine_due',
    domain: 'knowledge',
    snapshotId: 'knowledge.routine_due.knowledge_disabled',
    expectedStatus: AgentOutcomeRegressionStatus.noFinding,
    tags: <String>{kAgentOutcomeDomainOptOutTag},
  ),
];
