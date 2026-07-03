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
