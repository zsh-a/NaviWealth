import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
