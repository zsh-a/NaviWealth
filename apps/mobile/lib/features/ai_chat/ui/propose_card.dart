import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/composition/batch_proposal_undo.dart';
import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_kind_registry.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/ai/write/interaction_mode.dart';
import '../../../core/ai/write/providers.dart';
import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/chat_repository.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../state/chat_controller.dart';
import 'proposal_edit_sheet.dart';
import 'proposal_kind_labels.dart';
import 'proposal_payload_details.dart';

IconData _iconFor(List<ProposalKindMeta> registry, String kind) {
  return registry.metaFor(kind)?.icon ?? FLucideIcons.circleHelp;
}

/// Confirmation card rendered for `propose_*` tool calls.
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
  static const _undoWindow = Duration(seconds: 60);
  static const _uuid = Uuid();

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
    if (plan is BatchProposalPlan) {
      return _buildBatch(plan, _applyState);
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
        final mode = deriveInteractionModeForPlan(plan);
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

  Widget _buildBatch(BatchProposalPlan plan, ProposalApplyState state) {
    switch (state.status) {
      case ProposalApplyStatus.applied:
      case ProposalApplyStatus.undone:
      case ProposalApplyStatus.cancelled:
        return _BatchCollapsedView(
          plan: plan,
          applyState: state,
          onUndoRequest: state.status == ProposalApplyStatus.applied
              ? _onUndo
              : null,
        );
      case ProposalApplyStatus.pending:
      case ProposalApplyStatus.errored:
      case ProposalApplyStatus.applying:
        return _BatchProposalView(
          plan: plan,
          applyState: state,
          onConfirm: () => _onConfirmBatch(plan),
          onCancel: _onCancel,
        );
    }
  }

  Future<void> _persist(ProposalApplyState newState) async {
    final repo = await ref.read(chatRepositoryProvider.future);
    await _persistWithRepo(repo, newState);
  }

  Future<void> _persistWithRepo(
    ChatRepository repo,
    ProposalApplyState newState,
  ) async {
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

    final repo = await ref.read(chatRepositoryProvider.future);
    await _persistWithRepo(
      repo,
      _applyState.copyWith(status: ProposalApplyStatus.applying),
    );
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      final result = await applier.apply(effective);
      await _persistWithRepo(repo, result);
    } on ProposalApplyException catch (e) {
      Haptics.error();
      await _persistWithRepo(
        repo,
        _applyState.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: e.message,
        ),
      );
    } catch (e) {
      Haptics.error();
      await _persistWithRepo(
        repo,
        _applyState.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _onConfirmBatch(BatchProposalPlan plan) async {
    Haptics.primaryPress();
    final repo = await ref.read(chatRepositoryProvider.future);
    final stack = ref.read(undoStackProvider);
    await _persistWithRepo(
      repo,
      _applyState.copyWith(status: ProposalApplyStatus.applying),
    );
    final appliedChildren = <ProposalApplyState>[];
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      for (final child in plan.children) {
        final childState = await applier.apply(child);
        if (childState.status != ProposalApplyStatus.applied) {
          throw ProposalApplyException(
            childState.errorMessage ?? 'batch child did not apply',
          );
        }
        appliedChildren.add(childState);
      }
      final appliedAt = DateTime.now().toUtc();
      final childrenJson = [
        for (final childState in appliedChildren) childState.toJson(),
      ];
      String? undoToken;
      Map<String, Object?> undoData = <String, Object?>{
        'proposal_id': plan.proposalId,
        'child_count': appliedChildren.length,
      };
      if (stack != null) {
        undoToken = 'batch_undo:${plan.proposalId}:${_uuid.v4()}';
        await stack.put(
          buildBatchProposalUndoEntry(
            token: undoToken,
            proposalId: plan.proposalId,
            summaryZh: plan.summaryZh,
            chatSessionId: widget.sessionId,
            chatMessageId: widget.message.id,
            chatToolInvocationId: widget.invocation.id,
            children: appliedChildren,
            createdAt: appliedAt,
            expiresAt: appliedAt.add(_undoWindow),
          ),
        );
      } else {
        undoData = <String, Object?>{'children': childrenJson};
      }
      await _persistWithRepo(
        repo,
        ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedTable: kBatchProposalAppliedTable,
          appliedAt: appliedAt,
          undoData: undoData,
          undoToken: undoToken,
          shortLabel: plan.summaryZh,
        ),
      );
    } on Object catch (e) {
      await _undoAppliedBatchChildren(appliedChildren);
      Haptics.error();
      await _persistWithRepo(
        repo,
        _applyState.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: e is ProposalApplyException ? e.message : e.toString(),
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
    final repo = await ref.read(chatRepositoryProvider.future);
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      if (state.appliedTable == kBatchProposalAppliedTable) {
        await _undoBatchState(applier, state);
      } else {
        await applier.undo(state);
      }
      await _persistWithRepo(
        repo,
        state.copyWith(status: ProposalApplyStatus.undone),
      );
    } on ProposalApplyException catch (e) {
      await _persistWithRepo(
        repo,
        state.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: l10n.aiChatProposalUndoFailure(e.message),
        ),
      );
    } catch (e) {
      await _persistWithRepo(
        repo,
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

  Future<void> _undoAppliedBatchChildren(
    List<ProposalApplyState> children,
  ) async {
    if (children.isEmpty) return;
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      for (final childState in children.reversed) {
        await applier.undo(childState);
      }
    } catch (_) {
      // The apply failure is the user-visible error; rollback is best effort.
    }
  }

  Future<void> _undoBatchState(
    ProposalApplier applier,
    ProposalApplyState state,
  ) async {
    final token = state.undoToken;
    if (token != null) {
      final stack = ref.read(undoStackProvider);
      if (stack != null) {
        final entry = await stack.take(token);
        if (entry == null) {
          throw ProposalApplyException('batch undo entry missing');
        }
        if (entry.kind != kBatchProposalUndoKind) {
          throw ProposalApplyException(
            'unexpected batch undo kind: ${entry.kind}',
          );
        }
        return _undoBatchChildren(
          applier,
          batchProposalUndoChildren(entry.payload),
        );
      }
    }

    final undoData = state.undoData;
    if (undoData == null) {
      throw ProposalApplyException('batch undo data missing children');
    }
    final children = batchProposalUndoChildren(undoData);
    return _undoBatchChildren(applier, children);
  }

  Future<void> _undoBatchChildren(
    ProposalApplier applier,
    List<ProposalApplyState> children,
  ) async {
    for (final childState in children.reversed) {
      await applier.undo(childState);
    }
  }
}

class _BatchProposalView extends ConsumerWidget {
  const _BatchProposalView({
    required this.plan,
    required this.applyState,
    required this.onConfirm,
    required this.onCancel,
  });

  final BatchProposalPlan plan;
  final ProposalApplyState applyState;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(proposalKindRegistryProvider);
    final isApplying = applyState.status == ProposalApplyStatus.applying;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.s8),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.layers,
                size: AppIconSizes.h18,
                color: colors.foreground,
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                l10n.aiChatProposalBatchPending(plan.children.length),
                style: context.captionStyle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            plan.summaryZh,
            style: context.rowTitleStyle.copyWith(color: colors.foreground),
          ),
          const SizedBox(height: AppSpacing.s8),
          _BatchChildrenList(plan: plan, registry: registry),
          if (plan.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s10),
            _WarningCallout(warnings: plan.warnings),
          ],
          if (applyState.status == ProposalApplyStatus.errored &&
              applyState.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.aiChatProposalFailure(applyState.errorMessage!),
              style: context.captionStyle.copyWith(
                color: context.theme.colors.destructive,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            children: [
              FButton(
                variant: FButtonVariant.primary,
                onPress: isApplying ? null : onConfirm,
                prefix: const Icon(
                  FLucideIcons.checkCheck,
                  size: AppIconSizes.xs,
                ),
                child: Text(
                  isApplying
                      ? l10n.aiChatProposalApplying
                      : l10n.aiChatProposalBatchConfirmAll,
                ),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: isApplying ? null : onCancel,
                prefix: const Icon(FLucideIcons.x, size: AppIconSizes.xs),
                child: Text(l10n.commonCancel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BatchChildrenList extends StatelessWidget {
  const _BatchChildrenList({required this.plan, required this.registry});

  final BatchProposalPlan plan;
  final List<ProposalKindMeta> registry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: context.theme.colors.background.withValues(
          alpha: AppOpacity.prominent,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(
          color: context.theme.colors.border.withValues(
            alpha: AppOpacity.disabled,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < plan.children.length; i++)
            Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? AppSpacing.s0 : AppSpacing.s6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}.', style: context.microCaptionStyle),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      '${proposalKindLabel(l10n, registry, plan.children[i].kind)} · '
                      '${plan.children[i].summaryZh}',
                      style: context.captionStyle.copyWith(
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

class _BatchCollapsedView extends StatelessWidget {
  const _BatchCollapsedView({
    required this.plan,
    required this.applyState,
    required this.onUndoRequest,
  });

  final BatchProposalPlan plan;
  final ProposalApplyState applyState;
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
        label = applyState.shortLabel ?? plan.summaryZh;
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
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: FCard.raw(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            children: [
              Icon(icon, size: AppIconSizes.sm, color: color),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  label,
                  style: context.theme.typography.body.sm.copyWith(
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

class _ExpandedView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(proposalKindRegistryProvider);
    final isApplying = applyState.status == ProposalApplyStatus.applying;
    final isErrored = applyState.status == ProposalApplyStatus.errored;
    final summary = overrides == null
        ? plan.summaryZh
        : l10n.aiChatProposalSummaryEdited(plan.summaryZh);

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.s8),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconFor(registry, plan.kind),
                size: AppIconSizes.h18,
                color: colors.foreground,
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                l10n.aiChatProposalPendingHeader(
                  proposalKindLabel(l10n, registry, plan.kind),
                ),
                style: context.captionStyle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            summary,
            style: context.rowTitleStyle.copyWith(color: colors.foreground),
          ),
          const SizedBox(height: AppSpacing.s8),
          ProposalPayloadDetails(plan: plan, overrides: overrides),
          if (plan.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s10),
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
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.aiChatProposalFailure(applyState.errorMessage!),
              style: context.captionStyle.copyWith(
                color: context.theme.colors.destructive,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s4,
            children: [
              FButton(
                variant: FButtonVariant.primary,
                onPress: isApplying ? null : onConfirm,
                prefix: const Icon(FLucideIcons.check, size: AppIconSizes.xs),
                child: Text(
                  isApplying
                      ? l10n.aiChatProposalApplying
                      : l10n.aiChatProposalConfirm,
                ),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: isApplying ? null : onCancel,
                prefix: const Icon(FLucideIcons.x, size: AppIconSizes.xs),
                child: Text(l10n.commonCancel),
              ),
              FButton(
                variant: FButtonVariant.ghost,
                onPress: isApplying ? null : onEdit,
                prefix: const Icon(FLucideIcons.pencil, size: AppIconSizes.xs),
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
// InteractionMode.oneTap surface.
//
// Reserved for low-risk, easily-undoable proposals (memo edits, tag
// applies, category sets, small expense entries). The expanded diff
// preview is overkill for these — one tap should be enough. Errors
// still fall back to the full ExpandedView wording so users can read
// what went wrong.
// ───────────────────────────────────────────────────────────────────────────
class _OneTapView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(proposalKindRegistryProvider);
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.s8),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s10,
        AppSpacing.s8,
        AppSpacing.s10,
      ),
      decoration: BoxDecoration(
        color: AiTone.surfaceTint(
          context,
        ).withValues(alpha: AppOpacity.prominent),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AiSparkle(),
              const SizedBox(width: AppSpacing.s6),
              Text(
                proposalKindLabel(l10n, registry, plan.kind),
                style: AiType.meta(context),
              ),
              const Spacer(),
              if (_isApplying)
                const SizedBox(
                  width: AppIconSizes.xs,
                  height: AppIconSizes.xs,
                  child: FCircularProgress(size: .xs),
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
          const SizedBox(height: AppSpacing.s4),
          Text(
            plan.summaryZh,
            style: AiType.body(context),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (_isErrored && applyState.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(
              applyState.errorMessage!,
              style: AiType.meta(
                context,
              ).copyWith(color: AiTone.error(context)),
            ),
          ],
          const SizedBox(height: AppSpacing.s4),
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
// InteractionMode.typed surface.
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
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s12,
            AppSpacing.s8,
            AppSpacing.s12,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.aiChatProposalConfirmTokenWarning(_confirmToken),
                style: AiType.meta(
                  context,
                ).copyWith(color: AiTone.error(context)),
              ),
              const SizedBox(height: AppSpacing.s6),
              FTextField(
                control: FTextFieldControl.managed(controller: _controller),
                hint: _confirmToken,
              ),
              if (!_matches)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s4),
                  child: Text(
                    l10n.aiChatProposalConfirmTokenPending(_confirmToken),
                    style: AiType.meta(context),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s4),
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
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: FCard.raw(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            children: [
              Icon(icon, size: AppIconSizes.sm, color: color),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  label,
                  style: context.theme.typography.body.sm.copyWith(
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
    final registry = ref.watch(proposalKindRegistryProvider);
    final turn = ref.watch(chatControllerProvider(sessionId));
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: FCard.raw(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FLucideIcons.circleHelp,
                    size: AppIconSizes.h18,
                    color: colors.mutedForeground,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Text(
                    l10n.aiChatProposalNeedsClarificationHeader(
                      proposalKindLabel(l10n, registry, plan.kind),
                    ),
                    style: context.captionStyle.copyWith(
                      color: context.theme.colors.foreground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s6),
              Text(
                plan.reason,
                style: context.theme.typography.body.sm.copyWith(
                  color: context.theme.colors.foreground,
                ),
              ),
              if (plan.candidates.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s8),
                Text(
                  l10n.aiChatProposalCandidatesHeading,
                  style: context.microCaptionStyle,
                ),
                const SizedBox(height: AppSpacing.s4),
                // Tapping a candidate sends its label as the next user
                // turn so the clarification round-trips through the same
                // chat pipeline. Disabled while a turn is in flight
                // (`turn.isBusy`) to avoid stacking duplicate selects.
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s4,
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s10,
        AppSpacing.s8,
        AppSpacing.s10,
        AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: AiTone.surfaceTint(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border(
          left: BorderSide(
            color: AiTone.active(
              context,
            ).withValues(alpha: AppOpacity.prominent),
            width: AppStroke.branch,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < warnings.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  FLucideIcons.triangleAlert,
                  size: AppIconSizes.sm,
                  color: AiTone.onSurface(context),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    warnings[i],
                    style: context.captionMediumStyle.copyWith(
                      color: AiTone.onSurface(context),
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
