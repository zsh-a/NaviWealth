/// Wave 35 — `InteractionMode` derived from a [ProposalEnvelope].
///
/// The §5.5 doc rule: confirmation UI must come from `(risk,
/// side_effect)` — feature code is *not allowed* to hand-pick a mode.
/// Lowering an action's risk classification is the *only* way to make
/// it more frictionless, and that requires a code change to the
/// proposal kindLabel + matching descriptor.
///
/// Mapping table (must stay in sync with §5.5 of `docs/ai-architecture.md`).
/// `interactionModeForKindLabel` is single-sourced — the propose-card flow
/// in the UI calls it with the device propose tool's kindLabel string,
/// rather than constructing an envelope first.
///
///   - `LocalImmediateWrite`            → `swipe`   (already applied locally;
///                                                  the UI affordance is the
///                                                  persistent undo banner)
///   - `LocalProposal`                  → `confirmDiff`
///   - `ExternalSideEffect`             → `typed`
///   - kindLabel `broker_order` / `bulk_delete`               → `typed`
///   - kindLabel `rebalance` / `liability_payment` / `trade`
///       / `account_create` / `asset_valuation`               → `confirmDiff`
///   - kindLabel `expense` / `memo_edit` / `category_set`
///       / `tag_apply`                                        → `oneTap`
///       (small, easy to undo)
///   - anything unknown                                       → `confirmDiff`
///       (safe default)
library;

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

/// Public counterpart to [deriveInteractionMode] for callers that
/// already know the kind string but don't have a full envelope (e.g.
/// `propose_card.dart` passes `plan.kind`, the wire identifier).
/// Keeps the mapping single-sourced — the docstring table in this
/// file is authoritative.
InteractionMode interactionModeForKindLabel(String kindLabel) {
  return switch (kindLabel) {
    'broker_order' || 'bulk_delete' => InteractionMode.typed,
    'rebalance' ||
    'liability_payment' ||
    'trade' ||
    'account_create' ||
    'asset_valuation' => InteractionMode.confirmDiff,
    'expense' ||
    'memo_edit' ||
    'category_set' ||
    'tag_apply' => InteractionMode.oneTap,
    _ => InteractionMode.confirmDiff,
  };
}
