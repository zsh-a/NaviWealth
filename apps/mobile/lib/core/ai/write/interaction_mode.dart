/// `InteractionMode` derived from proposal side-effect scope.
///
/// The §5.5 doc rule: confirmation UI must come from `(risk,
/// side_effect)` — feature code is *not allowed* to hand-pick a mode.
/// Lowering an action's risk classification is the *only* way to make
/// it more frictionless, and that requires a code change to the
/// proposal kindLabel + matching descriptor.
///
///   - `LocalImmediateWrite`            → `swipe`   (already applied locally;
///                                                  the UI affordance is the
///                                                  persistent undo banner)
///   - `LocalProposal`                  → `confirmDiff`
///   - `ExternalSideEffect`             → `typed`
///
library;

import '../composition/proposal_plan.dart';
import '../contracts/proposal_envelope.dart';

enum InteractionMode {
  /// Apply immediately on tap. UI: single button, no preview. Reserved
  /// for low-risk reversible changes (note edit, tag, category).
  oneTap,

  /// Already applied locally, user dismisses or undoes via the
  /// persistent undo banner. UI: shows the applied state inline.
  swipe,

  /// User must see the full payload (diff / before-after) and tap
  /// Confirm. UI: expanded proposal card with `ProposalEditSheet`.
  confirmDiff,

  /// Highest friction. User must type a confirmation token (amount /
  /// "确认" / etc.) before Apply is enabled. UI: typed-confirm overlay.
  typed,
}

InteractionMode deriveInteractionMode(ProposalEnvelope p) {
  switch (p) {
    case ExternalSideEffect _:
      return InteractionMode.typed;
    case LocalImmediateWrite _:
      return InteractionMode.swipe;
    case LocalProposal _:
      return InteractionMode.confirmDiff;
    case BatchProposal batch:
      return _deriveBatchMode(batch);
  }
}

InteractionMode deriveInteractionModeForPlan(ProposalPlan plan) {
  return switch (plan) {
    ReadyProposalPlan ready => _modeForEnvelopeKind(ready.envelopeKind),
    BatchProposalPlan batch => _deriveBatchPlanMode(batch),
    ClarificationProposalPlan _ => InteractionMode.confirmDiff,
  };
}

InteractionMode _modeForEnvelopeKind(ProposalEnvelopeKind kind) {
  return switch (kind) {
    ProposalEnvelopeKind.localImmediate => InteractionMode.swipe,
    ProposalEnvelopeKind.localProposal => InteractionMode.confirmDiff,
    ProposalEnvelopeKind.externalSideEffect => InteractionMode.typed,
    ProposalEnvelopeKind.unknown => InteractionMode.typed,
  };
}

InteractionMode _deriveBatchPlanMode(BatchProposalPlan batch) {
  var rank = 0;
  for (final child in batch.children) {
    final childRank = _rankOf(deriveInteractionModeForPlan(child));
    if (childRank > rank) rank = childRank;
  }
  return _modeForRank(rank);
}

/// `roadmap-next.md` §4 M-2 — most-conservative-child wins. Order
/// (least → most friction): `oneTap` < `swipe` < `confirmDiff` <
/// `typed`. Batches never include `typed` children (the envelope
/// rejects [ExternalSideEffect] at construction), so the upper bound
/// is `confirmDiff`. Empty batches are unreachable — the envelope
/// asserts non-empty children.
InteractionMode _deriveBatchMode(BatchProposal batch) {
  var rank = 0;
  for (final child in batch.children) {
    final childRank = _rankOf(deriveInteractionMode(child));
    if (childRank > rank) rank = childRank;
  }
  return _modeForRank(rank);
}

int _rankOf(InteractionMode mode) {
  return switch (mode) {
    InteractionMode.oneTap => 0,
    InteractionMode.swipe => 1,
    InteractionMode.confirmDiff => 2,
    InteractionMode.typed => 3,
  };
}

InteractionMode _modeForRank(int rank) {
  return switch (rank) {
    0 => InteractionMode.oneTap,
    1 => InteractionMode.swipe,
    2 => InteractionMode.confirmDiff,
    _ => InteractionMode.typed,
  };
}
