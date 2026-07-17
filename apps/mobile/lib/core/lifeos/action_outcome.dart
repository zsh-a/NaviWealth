import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Domain-neutral outcome of comparing a completed action's source reference
/// with the current cross-domain signal set.
enum ActionOutcomeStatus {
  /// The source signal is no longer active in the current local snapshot.
  signalCleared,

  /// The same source signal is still active and may need another review.
  signalStillActive,
}

@immutable
class ActionOutcomeSummary {
  const ActionOutcomeSummary({required this.status, required this.sourceLabel});

  final ActionOutcomeStatus status;
  final String sourceLabel;
}

/// App-composed outcome summaries keyed by the action id owned by the
/// lifecycle domain. Core supplies an empty default so domain UI remains
/// independently testable and does not import sibling features.
final actionOutcomeSummariesProvider =
    Provider<Map<String, ActionOutcomeSummary>>((_) => const {});
