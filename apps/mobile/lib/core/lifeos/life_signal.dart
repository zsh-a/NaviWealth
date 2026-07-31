import 'package:flutter/foundation.dart';

import '../auth/domain_scope.dart';

/// Cross-domain attention signal rendered by the Life hub.
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
  final LifeActionSuggestion? actionSuggestion;
}

/// One complete observation contributed by a domain.
@immutable
class DomainLifeSignalSlice {
  const DomainLifeSignalSlice({
    this.events = const <LifeEvent>[],
    this.evaluatedSourceFamilies = const <String>{},
  });

  final List<LifeEvent> events;
  final Set<String> evaluatedSourceFamilies;
}

/// Complete observation consumed by outcome evaluation.
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

enum LifeEventTemplate {
  financeDaySummary,
  financeBudgetPressure,
  recoveryAlert,
  executionBlocked,
  executionDue,
  knowledgeInbox,
  agentResult,
}
