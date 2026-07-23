import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/ai/composition/batch_proposal_undo.dart';
import '../../../../core/ai/composition/proposal_applier.dart';
import '../../../../core/ai/composition/proposal_apply_state.dart';
import '../../../../core/ai/composition/proposal_kind_registry.dart';
import '../../../../core/ai/composition/proposal_plan.dart';
import '../../../../core/ai/contracts/interaction.dart';
import '../../../../core/ai/visual/visual.dart';
import '../../../../core/ai/write/interaction_mode.dart';
import '../../../../core/ai/write/providers.dart';
import '../../../../core/haptics/haptics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../application/batch_proposal_apply_coordinator.dart';
import '../../data/chat_repository.dart';
import '../../data/providers.dart';
import '../../domain/chat_models.dart';
import '../../state/chat_controller.dart';
import 'proposal_edit_sheet.dart';
import 'proposal_kind_labels.dart';
import 'proposal_payload_details.dart';

part 'batch_views.dart';
part 'mode_views.dart';
part 'support_views.dart';

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
        // Two visual tiers only:
        //  - light: oneTap
        //  - heavy: confirmDiff / swipe / typed (typed adds a token gate)
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
        final progress = BatchProposalProgress.fromState(
          state,
          total: plan.children.length,
        );
        final needsRecovery =
            state.status == ProposalApplyStatus.errored &&
            progress.requiresRecovery;
        return _BatchProposalView(
          plan: plan,
          applyState: state,
          onConfirm: needsRecovery
              ? () => _onRecoverBatch(plan)
              : () => _onConfirmBatch(plan),
          onCancel: _onCancel,
        );
    }
  }

  Future<void> _persist(
    ProposalApplyState newState, {
    AiInteractionResponse? interactionResponse,
  }) async {
    final repo = await ref.read(chatRepositoryProvider.future);
    await _persistWithRepo(
      repo,
      newState,
      interactionResponse: interactionResponse,
    );
  }

  Future<void> _persistWithRepo(
    ChatRepository repo,
    ProposalApplyState newState, {
    AiInteractionResponse? interactionResponse,
  }) async {
    await repo.updateToolApplyState(
      sessionId: widget.sessionId,
      messageId: widget.message.id,
      toolInvocationId: widget.invocation.id,
      newState: newState,
      interactionResponse: interactionResponse,
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
      interactionResponse: _proposalInteractionResponse(
        AiInteractionAction.approve,
      ),
    );
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      final result = await applier.apply(effective);
      Haptics.success();
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
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      final coordinator = BatchProposalApplyCoordinator(
        applier: applier,
        persist: (state) => _persistWithRepo(repo, state),
      );
      final result = await coordinator.execute(
        plan,
        finalize: (appliedChildren, appliedAt) async {
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
          return ProposalApplyState(
            status: ProposalApplyStatus.applied,
            appliedTable: kBatchProposalAppliedTable,
            appliedAt: appliedAt,
            undoData: undoData,
            undoToken: undoToken,
            shortLabel: plan.summaryZh,
          );
        },
      );
      if (result.status == ProposalApplyStatus.errored) Haptics.error();
    } on Object catch (e) {
      Haptics.error();
      await _persistWithRepo(
        repo,
        ProposalApplyState(
          status: ProposalApplyStatus.errored,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _onRecoverBatch(BatchProposalPlan plan) async {
    Haptics.primaryPress();
    final repo = await ref.read(chatRepositoryProvider.future);
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      final result = await BatchProposalApplyCoordinator(
        applier: applier,
        persist: (state) => _persistWithRepo(repo, state),
      ).recover(_applyState, total: plan.children.length);
      final progress = BatchProposalProgress.fromState(
        result,
        total: plan.children.length,
      );
      if (progress.requiresRecovery) Haptics.error();
    } on Object catch (e) {
      Haptics.error();
      await _persistWithRepo(
        repo,
        ProposalApplyState(
          status: ProposalApplyStatus.errored,
          errorMessage: e.toString(),
          undoData: _applyState.undoData,
        ),
      );
    }
  }

  Future<void> _onCancel() async {
    final plan = widget.plan;
    if (plan is ReadyProposalPlan) {
      try {
        final applier = await ref.read(proposalApplierProvider.future);
        if (applier is ProposalCancellationHandler) {
          await (applier as ProposalCancellationHandler).cancel(plan);
        }
      } on Object {
        // The chat decision remains authoritative. A failed best-effort
        // staging cleanup must not prevent the user from rejecting a plan.
      }
    }
    await _persist(
      _applyState.copyWith(status: ProposalApplyStatus.cancelled),
      interactionResponse: _proposalInteractionResponse(
        AiInteractionAction.reject,
      ),
    );
  }

  AiInteractionResponse? _proposalInteractionResponse(
    AiInteractionAction action,
  ) {
    final plan = widget.plan;
    if (plan is! ReadyProposalPlan || plan.interaction == null) return null;
    final interaction = plan.interaction!;
    return AiInteractionResponse(
      interactionId: interaction.interactionId,
      action: action,
      value: <String, Object?>{
        'proposal_id': plan.proposalId,
        'kind': plan.kind,
      },
      confirmationText: action == AiInteractionAction.approve
          ? interaction.confirmation?.requiredText
          : null,
      respondedAt: DateTime.now().toUtc(),
    );
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
