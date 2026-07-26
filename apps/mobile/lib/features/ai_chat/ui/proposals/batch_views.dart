part of 'propose_card.dart';

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
    final progress = BatchProposalProgress.fromState(
      applyState,
      total: plan.children.length,
    );
    final needsRecovery =
        applyState.status == ProposalApplyStatus.errored &&
        progress.requiresRecovery;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.s8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border, width: AppStroke.hairline),
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
                isApplying
                    ? l10n.aiChatProposalBatchProgress(
                        progress.completed,
                        progress.total,
                      )
                    : l10n.aiChatProposalBatchPending(plan.children.length),
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
          _BatchChildrenList(
            plan: plan,
            registry: registry,
            applyState: applyState,
          ),
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
          if (needsRecovery) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.aiChatProposalBatchRecoveryNeeded(
                progress.remainingChildren.length,
              ),
              style: context.captionStyle.copyWith(
                color: context.theme.colors.destructive,
              ),
            ),
          ] else if (applyState.status == ProposalApplyStatus.errored &&
              progress.rollbackComplete &&
              progress.completed > 0) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.aiChatProposalBatchRolledBack,
              style: context.captionStyle,
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
                      : needsRecovery
                      ? l10n.aiChatProposalBatchRecover
                      : l10n.aiChatProposalBatchConfirmAll,
                ),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: isApplying || needsRecovery ? null : onCancel,
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
  const _BatchChildrenList({
    required this.plan,
    required this.registry,
    required this.applyState,
  });

  final BatchProposalPlan plan;
  final List<ProposalKindMeta> registry;
  final ProposalApplyState applyState;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = BatchProposalProgress.fromState(
      applyState,
      total: plan.children.length,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: context.theme.colors.background.withValues(
          alpha: AppOpacity.prominent,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
                  SizedBox(
                    width: AppIconSizes.h18,
                    height: AppIconSizes.h18,
                    child: _BatchChildStatus(
                      index: i,
                      applyState: applyState,
                      progress: progress,
                    ),
                  ),
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

class _BatchChildStatus extends StatelessWidget {
  const _BatchChildStatus({
    required this.index,
    required this.applyState,
    required this.progress,
  });

  final int index;
  final ProposalApplyState applyState;
  final BatchProposalProgress progress;

  @override
  Widget build(BuildContext context) {
    if (applyState.status == ProposalApplyStatus.applying) {
      if (progress.recovering && index < progress.completed) {
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.s2),
          child: FCircularProgress(),
        );
      }
      if (index < progress.completed) {
        return Icon(
          FLucideIcons.check,
          size: AppIconSizes.xs,
          color: context.theme.colors.primary,
        );
      }
      if (index == progress.completed && !progress.recovering) {
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.s2),
          child: FCircularProgress(),
        );
      }
    }
    if (applyState.status == ProposalApplyStatus.errored) {
      if (index == progress.failedIndex) {
        return Icon(
          FLucideIcons.circleX,
          size: AppIconSizes.xs,
          color: context.theme.colors.destructive,
        );
      }
      if (index < progress.completed) {
        return Icon(
          progress.rollbackComplete
              ? FLucideIcons.undo2
              : FLucideIcons.triangleAlert,
          size: AppIconSizes.xs,
          color: progress.rollbackComplete
              ? context.theme.colors.mutedForeground
              : context.theme.colors.destructive,
        );
      }
    }
    return Center(
      child: Text('${index + 1}.', style: context.microCaptionStyle),
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
      padding: const EdgeInsets.only(top: AppSpacing.s6),
      child: Row(
        children: [
          Icon(icon, size: AppIconSizes.xs, color: color),
          const SizedBox(width: AppSpacing.s6),
          Expanded(
            child: Text(
              label,
              style: AiType.meta(context).copyWith(color: color),
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
    );
  }
}
