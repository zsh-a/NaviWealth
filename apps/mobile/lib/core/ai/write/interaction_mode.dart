/// Wave 35 — `InteractionMode` derived from a [ProposalEnvelope].
///
/// The §5.5 doc rule: confirmation UI must come from `(risk,
/// side_effect)` — feature code is *not allowed* to hand-pick a mode.
/// Lowering an action's risk classification is the *only* way to make
/// it more frictionless, and that requires a code change to the
/// proposal kindLabel + matching descriptor on the backend.
///
/// Mapping table (must stay in sync with `policy/tool_policy.rs`
/// propose entries and §5.5 of `docs/ai-architecture.md`):
///
///   - `LocalImmediateWrite`      → `swipe`   (already applied locally;
///                                            the UI affordance is the
///                                            persistent undo banner)
///   - `LocalProposal`            → `confirmDiff`
///   - `CloudProposal.broker_order`     → `typed`
///   - `CloudProposal.bulk_delete`      → `typed`
///   - `CloudProposal.rebalance`        → `confirmDiff`
///   - `CloudProposal.liability_payment`→ `confirmDiff`
///   - `CloudProposal.trade`            → `confirmDiff`
///   - `CloudProposal.account_create`   → `confirmDiff`
///   - `CloudProposal.asset_valuation`  → `confirmDiff`
///   - `CloudProposal.expense`          → `oneTap` (small, easy to undo)
///   - `CloudProposal.memo_edit`        → `oneTap`
///   - `CloudProposal.category_set`     → `oneTap`
///   - `CloudProposal.tag_apply`        → `oneTap`
///   - `ExternalSideEffect`             → `typed`
///   - anything unknown                 → `confirmDiff` (safe default)
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
    case CloudProposal cp:
      return interactionModeForKindLabel(cp.kindLabel);
  }
}

/// Public counterpart to [deriveInteractionMode] for callers that
/// already know the kind string but don't have a full envelope (e.g.
/// `propose_card.dart` derives from `ProposalKind.name`). Keeps the
/// mapping single-sourced — the docstring table in this file is
/// authoritative.
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
