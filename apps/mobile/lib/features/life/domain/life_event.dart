import 'package:flutter/foundation.dart';

import '../../../core/auth/domain_scope.dart';

/// Cross-domain attention signal for the Life hub.
///
/// Not a ledger feed. Each item answers "what needs attention across
/// domains?" — summaries and alerts only, never raw journal rows.
@immutable
class LifeEvent {
  const LifeEvent({
    required this.id,
    required this.at,
    required this.domain,
    required this.template,
    this.params = const <String>[],
    this.routePath,
    this.priority = LifeSignalPriority.normal,
    this.actionSuggestion,
  });

  final String id;
  final DateTime at;
  final DomainScope domain;
  final LifeEventTemplate template;
  final List<String> params;
  final String? routePath;
  final LifeSignalPriority priority;

  /// Optional, reviewable bridge from this cross-domain signal into
  /// ExecutionOS. The Life UI turns it into an `execution_action` proposal;
  /// this object never writes Execution rows directly.
  final LifeActionSuggestion? actionSuggestion;
}

/// One coherent observation of the cross-domain Life signal surface.
///
/// [evaluatedSourceFamilies] contains only source families whose upstream
/// provider produced a value without an error for this observation. Consumers
/// must not interpret an absent event as a cleared signal unless its family is
/// present in this set.
@immutable
class LifeSignalSnapshot {
  const LifeSignalSnapshot({
    required this.observedAt,
    required this.events,
    required this.evaluatedSourceFamilies,
  });

  final DateTime observedAt;
  final List<LifeEvent> events;
  final Set<String> evaluatedSourceFamilies;

  bool evaluated(String sourceRowFamily) =>
      evaluatedSourceFamilies.contains(sourceRowFamily);
}

/// Domain-neutral metadata for converting a Life signal into a concrete next
/// action. Visible copy is resolved by the Life UI so it stays localized.
@immutable
class LifeActionSuggestion {
  const LifeActionSuggestion({
    required this.template,
    required this.sourceRowFamily,
    this.sourceRowId,
  });

  final LifeActionTemplate template;
  final String sourceRowFamily;
  final String? sourceRowId;
}

enum LifeActionTemplate {
  reviewFinanceActivity,
  reviewFinanceBudget,
  protectRecovery,
  reviewKnowledgeInbox,
  reviewAgentInsight,
}

enum LifeSignalPriority { high, normal }

/// Signal templates resolved in the Life UI layer.
enum LifeEventTemplate {
  /// Today: N entries · net cash movement summary.
  financeDaySummary,

  /// Current-month spending is near or above the configured budget.
  financeBudgetPressure,

  /// Recovery is strained (or similar alert).
  recoveryAlert,

  /// N blocked execution actions.
  executionBlocked,

  /// N due / overdue open actions.
  executionDue,

  /// Knowledge inbox has open notes needing review.
  knowledgeInbox,

  /// A recent agent artifact is ready to open.
  agentResult,
}
