import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../core/ai/composition/proposal_applier.dart';
import '../../../../core/ai/composition/proposal_apply_state.dart';
import '../../../../core/ai/composition/proposal_plan.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data/providers.dart';
import '../../domain/chat_models.dart';

/// Batch action row shown above multiple pending propose cards in the same
/// assistant turn. Hidden when there's only zero or one ready proposals; the
/// per-card confirm button covers that case already.
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
      margin: const EdgeInsets.only(top: AppSpacing.s8),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(
            FLucideIcons.layers,
            size: AppIconSizes.h18,
            color: colors.primary,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              l10n.aiChatProposalBatchPending(widget.pending.length),
              style: context.captionStyle.copyWith(color: colors.primary),
            ),
          ),
          FButton(
            variant: FButtonVariant.primary,
            onPress: _busy ? null : _confirmAll,
            prefix: const Icon(FLucideIcons.checkCheck, size: AppIconSizes.xs),
            child: Text(l10n.aiChatProposalBatchConfirmAll),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAll() async {
    AppInteraction.signal(AppInteractionIntent.commit);
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
    AppMessenger.show(
      context,
      applied == 0 ? ToastKind.error : ToastKind.success,
      message,
    );
  }
}
