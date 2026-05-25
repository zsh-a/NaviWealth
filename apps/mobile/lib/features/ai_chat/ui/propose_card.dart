import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/visual/visual.dart';
import '../../../core/ai/write/interaction_mode.dart';
import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/proposal_applier.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../domain/proposal_apply_state.dart';
import '../domain/proposal_plan.dart';
import '../state/chat_controller.dart';

/// Wave 38 — bridge between mobile enum and the snake_case
/// `kindLabel` strings used by `interactionModeForKindLabel`. Must
/// stay in sync with `policy/tool_policy.rs` propose entries.
String _kindLabel(ProposalKind kind) => switch (kind) {
  ProposalKind.trade => 'trade',
  ProposalKind.expense => 'expense',
  ProposalKind.liabilityPayment => 'liability_payment',
  ProposalKind.accountCreate => 'account_create',
  ProposalKind.assetValuation => 'asset_valuation',
  ProposalKind.firePlanUpdate => 'fire_plan_update',
  ProposalKind.fireBucketRule => 'fire_bucket_rule',
  ProposalKind.unknown => '',
};

String proposalKindLabel(AppLocalizations l10n, ProposalKind kind) =>
    switch (kind) {
      ProposalKind.trade => l10n.aiChatProposalKindTrade,
      ProposalKind.expense => l10n.aiChatProposalKindExpense,
      ProposalKind.liabilityPayment => l10n.aiChatProposalKindLiabilityPayment,
      ProposalKind.accountCreate => l10n.aiChatProposalKindAccountCreate,
      ProposalKind.assetValuation => l10n.aiChatProposalKindAssetValuation,
      ProposalKind.firePlanUpdate => l10n.aiChatProposalKindFirePlanUpdate,
      ProposalKind.fireBucketRule => l10n.aiChatProposalKindFireBucketRule,
      ProposalKind.unknown => l10n.aiChatProposalKindUnknown,
    };

/// FIR-67 — confirmation card rendered for `propose_*` tool calls.
///
/// Single source of truth for the lifecycle: pending → applying → applied
/// → undone (or cancelled / errored). The persisted state lives on the
/// underlying `ToolInvocation.applyState`, so a chat reload reproduces
/// whatever decision the user made on this turn.
class ProposeCard extends ConsumerStatefulWidget {
  const ProposeCard({
    super.key,
    required this.sessionId,
    required this.message,
    required this.invocation,
    required this.plan,
  });

  final String sessionId;
  final ChatMessage message;
  final ToolInvocation invocation;
  final ProposalPlan plan;

  @override
  ConsumerState<ProposeCard> createState() => _ProposeCardState();
}

class _ProposeCardState extends ConsumerState<ProposeCard> {
  // Override values applied via the inline edit sheet, layered on top of
  // the original plan when the user finally confirms.
  Map<String, Object?>? _overrides;

  ProposalApplyState get _applyState =>
      widget.invocation.applyState ?? ProposalApplyState.pending;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    if (plan is ClarificationProposalPlan) {
      return _ClarificationView(plan: plan, sessionId: widget.sessionId);
    }
    if (plan is! ReadyProposalPlan) {
      return const SizedBox.shrink();
    }
    final state = _applyState;
    switch (state.status) {
      case ProposalApplyStatus.applied:
      case ProposalApplyStatus.undone:
      case ProposalApplyStatus.cancelled:
        return _CollapsedView(
          plan: plan,
          applyState: state,
          // The countdown widget owns the "is the window still open?"
          // gate now — we only have to say whether undo is *ever*
          // applicable for this state (i.e. the proposal was actually
          // applied, not cancelled / undone).
          onUndoRequest: state.status == ProposalApplyStatus.applied
              ? _onUndo
              : null,
        );
      case ProposalApplyStatus.pending:
      case ProposalApplyStatus.errored:
      case ProposalApplyStatus.applying:
        // Wave 38 — pick the confirmation surface from §5.5
        // `interactionModeForKindLabel`. oneTap (memo/category/tag/
        // small-expense) gets a slim Apply row; typed (broker order,
        // bulk delete — unused today) gates Confirm behind a token
        // field; everything else keeps the full diff/Confirm card.
        // `swipe` is treated as `confirmDiff` for now — a real
        // swipe-to-apply gesture is its own future wave.
        final mode = interactionModeForKindLabel(_kindLabel(plan.kind));
        return switch (mode) {
          InteractionMode.oneTap => _OneTapView(
            plan: plan,
            applyState: state,
            onConfirm: _onConfirm,
            onCancel: _onCancel,
            onEdit: () => _onEdit(plan),
          ),
          InteractionMode.typed => _TypedConfirmView(
            plan: plan,
            applyState: state,
            overrides: _overrides,
            onConfirm: _onConfirm,
            onCancel: _onCancel,
            onEdit: () => _onEdit(plan),
          ),
          InteractionMode.confirmDiff || InteractionMode.swipe => _ExpandedView(
            plan: plan,
            applyState: state,
            overrides: _overrides,
            onConfirm: _onConfirm,
            onCancel: _onCancel,
            onEdit: () => _onEdit(plan),
          ),
        };
    }
  }

  Future<void> _persist(ProposalApplyState newState) async {
    final repo = await ref.read(chatRepositoryProvider.future);
    await repo.updateToolApplyState(
      sessionId: widget.sessionId,
      messageId: widget.message.id,
      toolInvocationId: widget.invocation.id,
      newState: newState,
    );
  }

  Future<void> _onConfirm() async {
    final plan = widget.plan;
    if (plan is! ReadyProposalPlan) return;
    Haptics.primaryPress();
    final effective = _overrides == null
        ? plan
        : ReadyProposalPlan(
            proposalId: plan.proposalId,
            kind: plan.kind,
            summaryZh: plan.summaryZh,
            payload: <String, Object?>{...plan.payload, ..._overrides!},
            warnings: plan.warnings,
            missing: plan.missing,
          );

    await _persist(_applyState.copyWith(status: ProposalApplyStatus.applying));
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      final result = await applier.apply(effective);
      if (!mounted) return;
      await _persist(result);
    } on ProposalApplyException catch (e) {
      Haptics.error();
      await _persist(
        _applyState.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: e.message,
        ),
      );
    } catch (e) {
      Haptics.error();
      await _persist(
        _applyState.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _onCancel() async {
    await _persist(_applyState.copyWith(status: ProposalApplyStatus.cancelled));
  }

  Future<void> _onUndo() async {
    final l10n = AppLocalizations.of(context);
    final state = _applyState;
    if (state.status != ProposalApplyStatus.applied) return;
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      await applier.undo(state);
      if (!mounted) return;
      await _persist(state.copyWith(status: ProposalApplyStatus.undone));
    } on ProposalApplyException catch (e) {
      await _persist(
        state.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: l10n.aiChatProposalUndoFailure(e.message),
        ),
      );
    } catch (e) {
      await _persist(
        state.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: l10n.aiChatProposalUndoFailure(e.toString()),
        ),
      );
    }
  }

  Future<void> _onEdit(ReadyProposalPlan plan) async {
    final result = await showAppFormSheet<Map<String, Object?>>(
      context: context,
      builder: (_) => ProposalEditSheet(plan: plan, initial: _overrides),
    );
    if (result == null || !mounted) return;
    setState(() => _overrides = result);
  }
}

class _ExpandedView extends StatelessWidget {
  const _ExpandedView({
    required this.plan,
    required this.applyState,
    required this.overrides,
    required this.onConfirm,
    required this.onCancel,
    required this.onEdit,
  });

  final ReadyProposalPlan plan;
  final ProposalApplyState applyState;
  final Map<String, Object?>? overrides;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final isApplying = applyState.status == ProposalApplyStatus.applying;
    final isErrored = applyState.status == ProposalApplyStatus.errored;
    final summary = overrides == null
        ? plan.summaryZh
        : l10n.aiChatProposalSummaryEdited(plan.summaryZh);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(plan.kind), size: 18, color: colors.foreground),
              const SizedBox(width: 8),
              Text(
                l10n.aiChatProposalPendingHeader(
                  proposalKindLabel(l10n, plan.kind),
                ),
                style: context.theme.typography.xs.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: context.theme.typography.md.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ProposalPayloadDetails(plan: plan, overrides: overrides),
          if (plan.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Warnings are the user's last chance to spot a wrong
            // proposal before applying — they need to read as *content*,
            // not meta. We don't introduce a new warning hue (§5.6
            // AiTone discipline: one alive color, one alert color),
            // instead we lift them into a surfaceTint callout with an
            // accent stripe + heavier icon/weight so they stand out
            // against the body without going destructive-red.
            _WarningCallout(warnings: plan.warnings),
          ],
          if (isErrored && applyState.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.aiChatProposalFailure(applyState.errorMessage!),
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.destructive,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FButton(
                variant: FButtonVariant.primary,
                onPress: isApplying ? null : onConfirm,
                prefix: const Icon(FLucideIcons.check, size: 14),
                child: Text(
                  isApplying
                      ? l10n.aiChatProposalApplying
                      : l10n.aiChatProposalConfirm,
                ),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: isApplying ? null : onCancel,
                prefix: const Icon(FLucideIcons.x, size: 14),
                child: Text(l10n.commonCancel),
              ),
              FButton(
                variant: FButtonVariant.ghost,
                onPress: isApplying ? null : onEdit,
                prefix: const Icon(FLucideIcons.pencil, size: 14),
                child: Text(l10n.aiChatProposalEdit),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Wave 38 — InteractionMode.oneTap surface.
//
// Reserved for low-risk, easily-undoable proposals (memo edits, tag
// applies, category sets, small expense entries). The expanded diff
// preview is overkill for these — one tap should be enough. Errors
// still fall back to the full ExpandedView wording so users can read
// what went wrong.
// ───────────────────────────────────────────────────────────────────────────
class _OneTapView extends StatelessWidget {
  const _OneTapView({
    required this.plan,
    required this.applyState,
    required this.onConfirm,
    required this.onCancel,
    required this.onEdit,
  });

  final ReadyProposalPlan plan;
  final ProposalApplyState applyState;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onEdit;

  bool get _isApplying => applyState.status == ProposalApplyStatus.applying;
  bool get _isErrored => applyState.status == ProposalApplyStatus.errored;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AiTone.surfaceTint(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AiSparkle(),
              const SizedBox(width: 6),
              Text(
                proposalKindLabel(l10n, plan.kind),
                style: AiType.meta(context),
              ),
              const Spacer(),
              if (_isApplying)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              else
                AiPill(
                  // Retry on errored state — reuse the Confirm label;
                  // tapping again drives the same _onConfirm path
                  // which the apply state machine treats as a retry.
                  label: l10n.aiChatProposalConfirm,
                  state: AiPillState.selected,
                  onTap: _isApplying ? null : onConfirm,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            plan.summaryZh,
            style: AiType.body(context),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (_isErrored && applyState.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              applyState.errorMessage!,
              style: AiType.meta(
                context,
              ).copyWith(color: AiTone.error(context)),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              FButton(
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: _isApplying ? null : onEdit,
                child: Text(l10n.aiChatProposalEdit),
              ),
              FButton(
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: _isApplying ? null : onCancel,
                child: Text(l10n.commonCancel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Wave 38 — InteractionMode.typed surface.
//
// User must type a literal "确认" (or the proposal amount in future
// revisions) before Apply is enabled. Reserved for broker_order /
// bulk_delete-class proposals that no current backend tool generates —
// the view exists so the framework is ready when those tools ship.
// ───────────────────────────────────────────────────────────────────────────
class _TypedConfirmView extends StatefulWidget {
  const _TypedConfirmView({
    required this.plan,
    required this.applyState,
    required this.overrides,
    required this.onConfirm,
    required this.onCancel,
    required this.onEdit,
  });

  final ReadyProposalPlan plan;
  final ProposalApplyState applyState;
  final Map<String, Object?>? overrides;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onEdit;

  @override
  State<_TypedConfirmView> createState() => _TypedConfirmViewState();
}

class _TypedConfirmViewState extends State<_TypedConfirmView> {
  final _controller = TextEditingController();
  static const _confirmToken = '确认';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches => _controller.text.trim() == _confirmToken;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Reuse the expanded view's diff body, but disable its
        // Confirm button by swapping in a typed-confirm callback that
        // refuses unless the token matches.
        _ExpandedView(
          plan: widget.plan,
          applyState: widget.applyState,
          overrides: widget.overrides,
          onConfirm: () {
            if (_matches) widget.onConfirm();
          },
          onCancel: widget.onCancel,
          onEdit: widget.onEdit,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.aiChatProposalConfirmTokenWarning(_confirmToken),
                style: AiType.meta(
                  context,
                ).copyWith(color: AiTone.error(context)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _controller,
                onChanged: (_) => setState(() {}),
                style: AiType.body(context),
                decoration: InputDecoration(
                  hintText: _confirmToken,
                  hintStyle: AiType.body(
                    context,
                  ).copyWith(color: AiTone.muted(context)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AiTone.outline(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AiTone.error(context),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              if (!_matches)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.aiChatProposalConfirmTokenPending(_confirmToken),
                    style: AiType.meta(context),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.aiChatProposalConfirm,
                    style: AiType.meta(
                      context,
                    ).copyWith(color: AiTone.active(context)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CollapsedView extends StatelessWidget {
  const _CollapsedView({
    required this.plan,
    required this.applyState,
    required this.onUndoRequest,
  });

  final ReadyProposalPlan plan;
  final ProposalApplyState applyState;

  /// Invoked when the user taps the (self-ticking) undo button. `null`
  /// when this state can't be undone at all (already-undone / cancelled
  /// rows). The countdown widget owns the "is the 60s window still
  /// open?" question — we no longer pass a precomputed `onUndo` derived
  /// from `DateTime.now()`, which kept forcing the whole ProposeCard
  /// subtree to rebuild every second.
  final VoidCallback? onUndoRequest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final IconData icon;
    final Color color;
    final String label;
    switch (applyState.status) {
      case ProposalApplyStatus.applied:
        icon = FLucideIcons.circleCheck;
        color = context.theme.colors.primary;
        label =
            applyState.shortLabel ??
            l10n.aiChatProposalAppliedFallback(plan.summaryZh);
      case ProposalApplyStatus.undone:
        icon = FLucideIcons.undo;
        color = context.theme.colors.mutedForeground;
        label = l10n.aiChatProposalUndoneLabel(plan.summaryZh);
      case ProposalApplyStatus.cancelled:
        icon = FLucideIcons.circleX;
        color = context.theme.colors.mutedForeground;
        label = l10n.aiChatProposalCancelledLabel(plan.summaryZh);
      default:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FCard.raw(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: context.theme.typography.sm.copyWith(
                    color: context.theme.colors.foreground,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onUndoRequest != null &&
                  applyState.status == ProposalApplyStatus.applied &&
                  applyState.appliedAt != null)
                _UndoCountdownButton(
                  appliedAt: applyState.appliedAt!,
                  onUndo: onUndoRequest!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Self-contained 60-second undo button. Owns its own 1-second ticker
/// so the host `_ProposeCardState` no longer has to `setState` (and
/// rebuild every sibling sub-view: warnings, payload rows, …) every
/// second just to refresh a single label.
class _UndoCountdownButton extends StatefulWidget {
  const _UndoCountdownButton({required this.appliedAt, required this.onUndo});

  final DateTime appliedAt;
  final VoidCallback onUndo;

  @override
  State<_UndoCountdownButton> createState() => _UndoCountdownButtonState();
}

class _UndoCountdownButtonState extends State<_UndoCountdownButton> {
  static const int _windowSeconds = 60;
  Timer? _ticker;
  late int _secondsLeft;

  @override
  void initState() {
    super.initState();
    _recomputeSecondsLeft();
    if (_secondsLeft > 0) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(_recomputeSecondsLeft);
        if (_secondsLeft <= 0) {
          _ticker?.cancel();
          _ticker = null;
        }
      });
    }
  }

  @override
  void didUpdateWidget(_UndoCountdownButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appliedAt != widget.appliedAt) {
      _ticker?.cancel();
      _recomputeSecondsLeft();
      if (_secondsLeft > 0) {
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(_recomputeSecondsLeft);
          if (_secondsLeft <= 0) {
            _ticker?.cancel();
            _ticker = null;
          }
        });
      }
    }
  }

  void _recomputeSecondsLeft() {
    final elapsed = DateTime.now().difference(widget.appliedAt).inSeconds;
    _secondsLeft = _windowSeconds - elapsed;
    if (_secondsLeft < 0) _secondsLeft = 0;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsLeft <= 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return FButton(
      variant: FButtonVariant.ghost,
      onPress: widget.onUndo,
      prefix: const Icon(FLucideIcons.undo, size: 12),
      child: Text(l10n.aiChatProposalUndoCountdown(_secondsLeft)),
    );
  }
}

class _ClarificationView extends ConsumerWidget {
  const _ClarificationView({required this.plan, required this.sessionId});

  final ClarificationProposalPlan plan;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final turn = ref.watch(chatControllerProvider(sessionId));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FCard.raw(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FLucideIcons.circleHelp,
                    size: 18,
                    color: colors.mutedForeground,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.aiChatProposalNeedsClarificationHeader(
                      proposalKindLabel(l10n, plan.kind),
                    ),
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.foreground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                plan.reason,
                style: context.theme.typography.sm.copyWith(
                  color: context.theme.colors.foreground,
                ),
              ),
              if (plan.candidates.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.aiChatProposalCandidatesHeading,
                  style: context.theme.typography.xs2.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 4),
                // Tapping a candidate sends its label as the next user
                // turn so the clarification round-trips through the same
                // chat pipeline. Disabled while a turn is in flight
                // (`turn.isBusy`) to avoid stacking duplicate selects.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final c in plan.candidates)
                      AiPill(
                        label: c.label ?? c.id,
                        onTap: turn.isBusy
                            ? null
                            : () => ref
                                  .read(
                                    chatControllerProvider(sessionId).notifier,
                                  )
                                  .send(c.label ?? c.id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-field detail rows shown in the expanded card. Surfaces the bits of
/// the payload the user is most likely to want to verify (operation,
/// asset/account, amount, date, note) — anything the model included that
/// doesn't fit those slots stays inside the raw plan, accessible via the
/// edit sheet's "完整编辑" follow-up.
class ProposalPayloadDetails extends StatelessWidget {
  const ProposalPayloadDetails({super.key, required this.plan, this.overrides});

  final ReadyProposalPlan plan;
  final Map<String, Object?>? overrides;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = _rowsFor(l10n, plan, overrides);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.theme.colors.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: context.theme.colors.border.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      r.label,
                      style: context.theme.typography.xs2.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.value,
                      style: context.theme.typography.xs.copyWith(
                        color: context.theme.colors.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Inline edit sheet: lets the user override the high-frequency fields
/// (amount / price / note / date) before they confirm. Anything beyond
/// these flows back to the full FIR-44 / FIR-63 / FIR-64 entry pages —
/// surfaced as a compact Forui action at the bottom of the sheet.
class ProposalEditSheet extends StatefulWidget {
  const ProposalEditSheet({super.key, required this.plan, this.initial});

  final ReadyProposalPlan plan;
  final Map<String, Object?>? initial;

  @override
  State<ProposalEditSheet> createState() => _ProposalEditSheetState();
}

class _ProposalEditSheetState extends State<ProposalEditSheet> {
  /// Lazy controller bag — populated as fields become visible. Keeping
  /// the values across mode toggles means typing in standard mode,
  /// flipping to full, and flipping back doesn't reset edits.
  final Map<String, TextEditingController> _controllers = {};
  List<_EditableField> _curated = const <_EditableField>[];
  bool _fullMode = false;
  bool _initialized = false;

  /// Payload keys that are bookkeeping rather than user content — never
  /// surface them in the editor.
  static const _internalKeys = <String>{'id', 'proposal_id', 'request_id'};

  void _ensureInitialized(AppLocalizations l10n) {
    if (_initialized) return;
    _initialized = true;
    _curated = _editableFieldsFor(l10n, widget.plan.kind);
    for (final f in _curated) {
      _controllers[f.payloadKey] = TextEditingController(
        text: _initialFor(f.payloadKey),
      );
    }
    // Kinds with no curated fields (FIRE proposals, unknown) must still
    // be editable — promote them straight into full mode so the sheet
    // isn't empty.
    if (_curated.isEmpty) _fullMode = true;
  }

  /// Curated + extras (when in full mode), preserving the curated order
  /// at the top so the most-frequent fields stay where users expect
  /// them after toggling.
  List<_EditableField> _currentFields() {
    if (!_fullMode) return _curated;
    final covered = <String>{for (final f in _curated) f.payloadKey};
    final extras = <_EditableField>[];
    for (final key in widget.plan.payload.keys) {
      if (covered.contains(key)) continue;
      if (_internalKeys.contains(key) || key.startsWith('_')) continue;
      _controllers.putIfAbsent(
        key,
        () => TextEditingController(text: _initialFor(key)),
      );
      extras.add(_EditableField(payloadKey: key, label: _humanize(key)));
    }
    return [..._curated, ...extras];
  }

  bool get _hasExtraFields {
    final covered = <String>{for (final f in _curated) f.payloadKey};
    for (final key in widget.plan.payload.keys) {
      if (covered.contains(key)) continue;
      if (_internalKeys.contains(key) || key.startsWith('_')) continue;
      return true;
    }
    return false;
  }

  static String _humanize(String snakeCase) => snakeCase.replaceAll('_', ' ');

  String _initialFor(String key) {
    final overridden = widget.initial?[key];
    if (overridden != null) return overridden.toString();
    final raw = widget.plan.payload[key];
    return raw == null ? '' : raw.toString();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _collect() {
    final out = <String, Object?>{};
    // Collect from every controller the user has ever seen so flipping
    // to full mode, editing, then collapsing back doesn't lose the
    // extra-field edits.
    for (final entry in _controllers.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) {
        // Setting empty preserves the underlying value — applier reads
        // payload via plan.get() which already treats empty as absent.
        continue;
      }
      out[entry.key] = text;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _ensureInitialized(l10n);
    final fields = _currentFields();
    // Toggle is meaningful only when both modes have content. If the
    // kind has no curated fields we silently force full mode; if there
    // are no extra payload keys beyond curated, there's nowhere to
    // expand to.
    final showToggle = _curated.isNotEmpty && _hasExtraFields;
    return AppSheet(
      title: l10n.aiChatProposalEditKindTitle(
        proposalKindLabel(l10n, widget.plan.kind),
      ),
      footer: AppSheetFooter(
        submitLabel: l10n.aiChatProposalSaveEdits,
        cancelLabel: l10n.commonCancel,
        onSubmit: () => Navigator.of(context).pop(_collect()),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in fields) ...[
            FTextField(
              control: FTextFieldControl.managed(
                controller: _controllers[f.payloadKey],
              ),
              keyboardType: f.numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              label: Text(f.label),
              hint: f.hint,
            ),
            const SizedBox(height: 12),
          ],
          if (showToggle)
            Align(
              alignment: Alignment.centerLeft,
              child: FTappable(
                onPress: () => setState(() => _fullMode = !_fullMode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _fullMode
                            ? FLucideIcons.chevronUp
                            : FLucideIcons.chevronDown,
                        size: 16,
                        color: AiTone.active(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _fullMode
                            ? l10n.aiChatProposalEditStandardFields
                            : l10n.aiChatProposalEditMoreFields,
                        style: AiType.meta(
                          context,
                        ).copyWith(color: AiTone.active(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditableField {
  const _EditableField({
    required this.payloadKey,
    required this.label,
    this.hint,
    this.numeric = false,
  });
  final String payloadKey;
  final String label;
  final String? hint;
  final bool numeric;
}

List<_EditableField> _editableFieldsFor(
  AppLocalizations l10n,
  ProposalKind kind,
) {
  switch (kind) {
    case ProposalKind.trade:
      return [
        _EditableField(
          payloadKey: 'quantity',
          label: l10n.aiChatFieldQuantity,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'price',
          label: l10n.aiChatFieldPrice,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'fee',
          label: l10n.aiChatFieldFee,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'tax',
          label: l10n.aiChatFieldTax,
          numeric: true,
        ),
        _EditableField(payloadKey: 'note', label: l10n.aiChatFieldNote),
      ];
    case ProposalKind.expense:
      return [
        _EditableField(
          payloadKey: 'amount',
          label: l10n.aiChatFieldAmount,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'date',
          label: l10n.aiChatFieldDate,
          hint: l10n.aiChatFieldDateHint,
        ),
        _EditableField(payloadKey: 'note', label: l10n.aiChatFieldNote),
      ];
    case ProposalKind.liabilityPayment:
      return [
        _EditableField(
          payloadKey: 'amount',
          label: l10n.aiChatFieldAmount,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'date',
          label: l10n.aiChatFieldDate,
          hint: l10n.aiChatFieldDateHint,
        ),
        _EditableField(payloadKey: 'note', label: l10n.aiChatFieldNote),
      ];
    case ProposalKind.accountCreate:
      return [
        _EditableField(payloadKey: 'name', label: l10n.aiChatFieldAccountName),
        _EditableField(
          payloadKey: 'institution',
          label: l10n.aiChatFieldInstitution,
        ),
        _EditableField(payloadKey: 'note', label: l10n.aiChatFieldNote),
      ];
    case ProposalKind.assetValuation:
      return [
        _EditableField(
          payloadKey: 'new_value',
          label: l10n.aiChatFieldNewValuation,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'date',
          label: l10n.aiChatFieldDate,
          hint: l10n.aiChatFieldDateHint,
        ),
        _EditableField(payloadKey: 'note', label: l10n.aiChatFieldNote),
      ];
    case ProposalKind.firePlanUpdate:
    case ProposalKind.fireBucketRule:
      // FIRE OS proposals don't expose payload fields for inline edit;
      // the diff is rendered via the existing `payload.before` /
      // `payload.after` shape and applied verbatim on confirm.
      return const [];
    case ProposalKind.unknown:
      return const [];
  }
}

class _Row {
  const _Row(this.label, this.value);
  final String label;
  final String value;
}

List<_Row> _rowsFor(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  String? read(String key) {
    final ov = overrides?[key];
    if (ov is String && ov.isNotEmpty) return ov;
    final v = plan.payload[key];
    if (v == null) return null;
    final s = v is String ? v : v.toString();
    return s.isEmpty ? null : s;
  }

  switch (plan.kind) {
    case ProposalKind.trade:
      return [
        if (read('type') != null)
          _Row(l10n.aiChatRowOperation, _tradeTypeLabel(l10n, read('type')!)),
        if (read('asset_symbol') != null || read('asset_name') != null)
          _Row(
            l10n.aiChatRowAsset,
            read('asset_name') != null && read('asset_symbol') != null
                ? '${read('asset_name')} (${read('asset_symbol')})'
                : (read('asset_name') ?? read('asset_symbol')!),
          ),
        if (read('account_name') != null)
          _Row(l10n.aiChatRowAccount, read('account_name')!),
        if (read('quantity') != null)
          _Row(l10n.aiChatRowQuantity, read('quantity')!),
        if (read('price') != null)
          _Row(
            l10n.aiChatRowPrice,
            '${read('price')} ${read('currency') ?? ''}'.trim(),
          ),
        if (read('fee') != null && read('fee') != '0' && read('fee') != '0.0')
          _Row(l10n.aiChatRowFee, read('fee')!),
        if (read('trade_date') != null)
          _Row(l10n.aiChatRowDate, read('trade_date')!),
        if (read('note') != null) _Row(l10n.aiChatRowNote, read('note')!),
      ];
    case ProposalKind.expense:
      return [
        if (read('amount') != null)
          _Row(
            l10n.aiChatRowAmount,
            '${read('amount')} ${read('currency') ?? ''}'.trim(),
          ),
        if (read('category') != null)
          _Row(l10n.aiChatRowCategory, read('category')!),
        if (read('account_name') != null)
          _Row(l10n.aiChatRowAccount, read('account_name')!),
        if (read('date') != null) _Row(l10n.aiChatRowDate, read('date')!),
        if (read('note') != null) _Row(l10n.aiChatRowNote, read('note')!),
      ];
    case ProposalKind.liabilityPayment:
      return [
        if (read('liability_name') != null)
          _Row(l10n.aiChatRowLiability, read('liability_name')!),
        if (read('amount') != null)
          _Row(
            l10n.aiChatRowAmount,
            '${read('amount')} ${read('currency') ?? ''}'.trim(),
          ),
        if (read('from_account_name') != null)
          _Row(l10n.aiChatRowRepayAccount, read('from_account_name')!),
        if (read('date') != null) _Row(l10n.aiChatRowDate, read('date')!),
        if (read('note') != null) _Row(l10n.aiChatRowNote, read('note')!),
      ];
    case ProposalKind.accountCreate:
      return [
        if (read('name') != null) _Row(l10n.aiChatRowName, read('name')!),
        if (read('type') != null) _Row(l10n.aiChatRowType, read('type')!),
        if (read('currency') != null)
          _Row(l10n.aiChatRowCurrency, read('currency')!),
        if (read('institution') != null)
          _Row(l10n.aiChatRowInstitution, read('institution')!),
        if (read('note') != null) _Row(l10n.aiChatRowNote, read('note')!),
      ];
    case ProposalKind.assetValuation:
      return [
        if (read('asset_name') != null)
          _Row(l10n.aiChatRowAsset, read('asset_name')!),
        if (read('new_value') != null)
          _Row(
            l10n.aiChatRowNewValue,
            '${read('new_value')} ${read('currency') ?? ''}'.trim(),
          ),
        if (read('date') != null) _Row(l10n.aiChatRowDate, read('date')!),
        if (read('note') != null) _Row(l10n.aiChatRowNote, read('note')!),
      ];
    case ProposalKind.firePlanUpdate:
      // The applier reads `payload.after`; surface it as a single row
      // so the confirm card still shows what's about to change.
      return [_Row(l10n.aiChatRowNote, plan.summaryZh)];
    case ProposalKind.fireBucketRule:
      return [
        if (read('role') != null) _Row(l10n.aiChatRowNote, plan.summaryZh),
      ];
    case ProposalKind.unknown:
      return const [];
  }
}

IconData _iconFor(ProposalKind kind) => switch (kind) {
  ProposalKind.trade => FLucideIcons.trendingUp,
  ProposalKind.expense => FLucideIcons.receipt,
  ProposalKind.liabilityPayment => FLucideIcons.banknote,
  ProposalKind.accountCreate => FLucideIcons.landmark,
  ProposalKind.assetValuation => FLucideIcons.refreshCw,
  ProposalKind.firePlanUpdate => FLucideIcons.flag,
  ProposalKind.fireBucketRule => FLucideIcons.slidersHorizontal,
  ProposalKind.unknown => FLucideIcons.circleHelp,
};

String _tradeTypeLabel(AppLocalizations l10n, String wire) => switch (wire) {
  'buy' => l10n.tradeTypeBuy,
  'sell' => l10n.tradeTypeSell,
  'transferIn' => l10n.tradeTypeTransferIn,
  'transferOut' => l10n.tradeTypeTransferOut,
  'valuationAdjust' => l10n.tradeTypeValuationAdjust,
  _ => wire,
};

/// Batch action row shown above multiple pending propose cards in the
/// same assistant turn. Hidden when there's only zero or one ready
/// proposals — the per-card confirm button covers that case already.
class ProposeBatchActions extends ConsumerStatefulWidget {
  const ProposeBatchActions({
    super.key,
    required this.sessionId,
    required this.message,
    required this.pending,
  });

  final String sessionId;
  final ChatMessage message;

  /// (invocation, plan) pairs that are still in `pending` status. Caller
  /// pre-filters; rendering a batch button when there's only one pending
  /// card is just visual noise.
  final List<({ToolInvocation invocation, ReadyProposalPlan plan})> pending;

  @override
  ConsumerState<ProposeBatchActions> createState() =>
      _ProposeBatchActionsState();
}

class _ProposeBatchActionsState extends ConsumerState<ProposeBatchActions> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    if (widget.pending.length < 2) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(FLucideIcons.layers, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.aiChatProposalBatchPending(widget.pending.length),
              style: context.theme.typography.xs.copyWith(
                color: colors.primary,
              ),
            ),
          ),
          FButton(
            variant: FButtonVariant.primary,
            onPress: _busy ? null : _confirmAll,
            prefix: const Icon(FLucideIcons.checkCheck, size: 14),
            child: Text(l10n.aiChatProposalBatchConfirmAll),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAll() async {
    Haptics.primaryPress();
    setState(() => _busy = true);
    var applied = 0;
    var failed = 0;
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      final repo = await ref.read(chatRepositoryProvider.future);
      for (final entry in widget.pending) {
        final state = entry.invocation.applyState ?? ProposalApplyState.pending;
        if (state.status != ProposalApplyStatus.pending &&
            state.status != ProposalApplyStatus.errored) {
          continue;
        }
        await repo.updateToolApplyState(
          sessionId: widget.sessionId,
          messageId: widget.message.id,
          toolInvocationId: entry.invocation.id,
          newState: state.copyWith(status: ProposalApplyStatus.applying),
        );
        try {
          final result = await applier.apply(entry.plan);
          await repo.updateToolApplyState(
            sessionId: widget.sessionId,
            messageId: widget.message.id,
            toolInvocationId: entry.invocation.id,
            newState: result,
          );
          if (result.status == ProposalApplyStatus.applied) {
            applied++;
          } else {
            failed++;
          }
        } on ProposalApplyException catch (e) {
          await repo.updateToolApplyState(
            sessionId: widget.sessionId,
            messageId: widget.message.id,
            toolInvocationId: entry.invocation.id,
            newState: state.copyWith(
              status: ProposalApplyStatus.errored,
              errorMessage: e.message,
            ),
          );
          failed++;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Each per-card view already flips to its applied / errored
        // surface, but with N items in a turn it's still easy to lose
        // track of "did anything fail?". The batch snackbar gives one
        // unambiguous result line.
        _showBatchSnackbar(applied: applied, failed: failed);
      }
    }
  }

  void _showBatchSnackbar({required int applied, required int failed}) {
    if (applied == 0 && failed == 0) return;
    final l10n = AppLocalizations.of(context);
    final String message;
    if (failed == 0) {
      message = l10n.aiChatProposalBatchResultAllOk(applied);
    } else if (applied == 0) {
      message = l10n.aiChatProposalBatchResultAllFailed(failed);
    } else {
      message = l10n.aiChatProposalBatchResultMixed(applied, failed);
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}

/// Surfaces propose-plan warnings so the user actually notices them
/// before tapping Confirm. Stays within the AiTone discipline (no new
/// warning hue): the visual hook is a surface-tint container + a 2px
/// accent stripe + bolder icon/text, not a saturated yellow.
class _WarningCallout extends StatelessWidget {
  const _WarningCallout({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AiTone.surfaceTint(context),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: AiTone.active(context).withValues(alpha: 0.6),
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < warnings.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  FLucideIcons.triangleAlert,
                  size: 16,
                  color: AiTone.onSurface(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warnings[i],
                    style: context.theme.typography.xs.copyWith(
                      color: AiTone.onSurface(context),
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
