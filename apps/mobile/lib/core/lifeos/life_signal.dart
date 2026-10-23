import 'package:flutter/foundation.dart';

import '../ai/contracts/source_identity.dart';
import '../auth/domain_scope.dart';
import 'action_dispatcher.dart';

enum LifeSourceEvaluationStatus { complete, pending, incomplete, failed }

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
    this.evidence = const <SourceIdentity>[],
  });

  final String id;
  final DateTime at;
  final DomainScope domain;
  final LifeEventTemplate template;
  final List<String> params;
  final String? routePath;
  final LifeSignalPriority priority;
  final LifeActionSuggestion? actionSuggestion;
  final List<SourceIdentity> evidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'at': at.toUtc().toIso8601String(),
    'domain': domain.wire,
    'template': template.name,
    'params': params,
    if (routePath != null) 'route_path': routePath,
    'priority': priority.name,
    if (actionSuggestion != null)
      'action_suggestion': actionSuggestion!.toJson(),
    'evidence': [for (final source in evidence) source.toJson()],
  };
}

/// One complete observation contributed by a domain.
@immutable
class DomainLifeSignalSlice {
  const DomainLifeSignalSlice({
    this.events = const <LifeEvent>[],
    this.evaluatedSourceFamilies = const <String>{},
    this.sourceEvaluations = const {},
  });

  final List<LifeEvent> events;
  final Set<String> evaluatedSourceFamilies;

  /// Exact identities covered by this observation, including failed reads.
  /// A successfully read family alone does not prove an older row was checked.
  final Map<LifeActionSource, LifeSourceEvaluationStatus> sourceEvaluations;
}

/// Complete observation consumed by outcome evaluation.
@immutable
class LifeSignalSnapshot {
  const LifeSignalSnapshot({
    required this.observedAt,
    required this.events,
    required this.evaluatedSourceFamilies,
    this.evaluatedSourceFamiliesByDomain = const <DomainScope, Set<String>>{},
    this.sourceEvaluations = const {},
  });

  final DateTime observedAt;
  final List<LifeEvent> events;
  final Set<String> evaluatedSourceFamilies;
  final Map<DomainScope, Set<String>> evaluatedSourceFamiliesByDomain;
  final Map<LifeActionSource, LifeSourceEvaluationStatus> sourceEvaluations;

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

  Map<String, Object?> toJson() => <String, Object?>{
    'template': template.name,
    'source_row_family': sourceRowFamily,
    if (sourceRowId != null) 'source_row_id': sourceRowId,
  };
}

enum LifeActionTemplate {
  reviewFinanceActivity,
  reviewFinanceBudget,
  protectRecovery,
}

enum LifeSignalPriority { high, normal }

enum LifeEventTemplate {
  financeDaySummary,
  financeBudgetPressure,
  recoveryAlert,
  executionBlocked,
  executionDue,
}
