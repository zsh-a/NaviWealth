import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LifeClosedActionStatus { done, dropped }

@immutable
class LifeClosedAction {
  const LifeClosedAction({
    required this.id,
    required this.status,
    required this.completedAt,
    required this.sourceRowFamily,
    required this.sourceRowId,
  });

  final String id;
  final LifeClosedActionStatus status;
  final DateTime completedAt;
  final String? sourceRowFamily;
  final String? sourceRowId;
}

/// Domain-neutral stream of completed lifecycle actions. Source domains can
/// observe their own row-family references without importing ExecutionOS.
final lifeClosedActionsProvider = Provider<AsyncValue<List<LifeClosedAction>>>(
  (_) => const AsyncValue.data(<LifeClosedAction>[]),
);

/// Domain-neutral outcome of comparing a completed action's source reference
/// with the current cross-domain signal set.
enum ActionOutcomeStatus {
  /// The source signal was not detected in a later, complete local snapshot.
  signalCleared,

  /// The same source signal was detected in a later local snapshot.
  signalStillActive,
}

/// Attribution boundary for cross-domain outcome copy.
///
/// A before/after observation can describe change, but cannot establish that
/// completing the Execution action caused that change.
enum ActionOutcomeAttribution { observational }

@immutable
class ActionOutcomeSummary {
  const ActionOutcomeSummary({
    required this.status,
    required this.sourceLabel,
    required this.sourceCapturedAt,
    required this.evaluatedAt,
    this.attribution = ActionOutcomeAttribution.observational,
  });

  final ActionOutcomeStatus status;
  final String sourceLabel;
  final DateTime sourceCapturedAt;
  final DateTime evaluatedAt;
  final ActionOutcomeAttribution attribution;
}

/// App-composed outcome summaries keyed by the action id owned by the
/// lifecycle domain. Core supplies an empty default so domain UI remains
/// independently testable and does not import sibling features.
final actionOutcomeSummariesProvider =
    Provider<Map<String, ActionOutcomeSummary>>((_) => const {});
