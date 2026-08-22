part of '../rebalance_execution_workspace_page.dart';

class _ExecutionMasterRow extends StatelessWidget {
  const _ExecutionMasterRow({
    required this.item,
    required this.selected,
    required this.focused,
    required this.selectable,
    required this.busy,
    required this.onSelectionChanged,
    required this.onFocus,
  });

  final RebalanceExecutionItem item;
  final bool selected;
  final bool focused;
  final bool selectable;
  final bool busy;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final target =
        item.suggestion.targetLabel ??
        AssetCategoryVisuals.label(l10n, item.suggestion.category);
    final direction = item.suggestion.isBuy
        ? l10n.rebalanceBuy
        : l10n.rebalanceSell;
    return Semantics(
      key: ValueKey('rebalance-master-${item.id}'),
      container: true,
      button: true,
      selected: focused,
      enabled: !busy,
      onTap: busy ? null : onFocus,
      child: AppTappable(
        onPress: busy ? null : onFocus,
        child: AnimatedContainer(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s10,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.muted : colors.background,
            border: Border.all(
              color: focused ? colors.primary : colors.border,
              width: focused ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              if (selectable) ...[
                Checkbox.adaptive(
                  value: selected,
                  semanticLabel: '$direction $target',
                  onChanged: busy
                      ? null
                      : (value) => onSelectionChanged(value ?? false),
                ),
                const SizedBox(width: AppSpacing.s4),
              ],
              Icon(
                AssetCategoryVisuals.icon(item.suggestion.category),
                size: AppIconSizes.h18,
                color: focused ? colors.primary : colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$direction $target',
                      style: context.labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      _stateLabel(l10n, item.state),
                      style: context.captionStyle.copyWith(
                        color:
                            item.issue?.recoveryAction ==
                                RebalanceRecoveryAction.none
                            ? colors.destructive
                            : colors.mutedForeground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AnimatedMoneyText(
                amount: item.suggestion.amount.amount.toDouble(),
                currencyCode: item.suggestion.amount.currency,
                compact: true,
                showSign: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExecutionItemRow extends StatelessWidget {
  const _ExecutionItemRow({
    required this.item,
    required this.selected,
    required this.focused,
    required this.selectable,
    required this.mutable,
    required this.busy,
    this.showSelection = true,
    required this.onReview,
    required this.onSkip,
    required this.onReopen,
    required this.onSelectionChanged,
    required this.onFocus,
  });

  final RebalanceExecutionItem item;
  final bool selected;
  final bool focused;
  final bool selectable;
  final bool mutable;
  final bool busy;
  final bool showSelection;
  final VoidCallback onReview;
  final VoidCallback onSkip;
  final VoidCallback onReopen;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reviewAction = item.issue?.recoveryAction;
    final canEnterManualPrice =
        item.request?.price == null &&
        const {
          RebalanceExecutionIssueCode.priceRequired,
          RebalanceExecutionIssueCode.applyUnavailable,
        }.contains(item.issue?.code);
    final canReview =
        mutable &&
        (const {
              RebalanceExecutionItemState.needsDetails,
              RebalanceExecutionItemState.ready,
            }.contains(item.state) ||
            reviewAction == RebalanceRecoveryAction.enterPrice ||
            reviewAction == RebalanceRecoveryAction.editReview ||
            canEnterManualPrice);
    final canSkip =
        mutable &&
        const {
          RebalanceExecutionItemState.needsDetails,
          RebalanceExecutionItemState.ready,
          RebalanceExecutionItemState.applyFailed,
        }.contains(item.state);
    final skipped =
        mutable && item.state == RebalanceExecutionItemState.skipped;
    final target =
        item.suggestion.targetLabel ??
        AssetCategoryVisuals.label(l10n, item.suggestion.category);
    final direction = item.suggestion.isBuy
        ? l10n.rebalanceBuy
        : l10n.rebalanceSell;
    final stackAmount = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final amount = AnimatedMoneyText(
      amount: item.suggestion.amount.amount.toDouble(),
      currencyCode: item.suggestion.amount.currency,
      compact: true,
      showSign: false,
    );
    return AppTappable(
      onPress: onFocus,
      semanticsLabel: '$direction $target',
      selected: focused,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSelection && selectable) ...[
              Checkbox.adaptive(
                value: selected,
                onChanged: busy
                    ? null
                    : (value) => onSelectionChanged(value ?? false),
              ),
              const SizedBox(width: AppSpacing.s4),
            ],
            Icon(
              AssetCategoryVisuals.icon(item.suggestion.category),
              size: AppIconSizes.h18,
              color: focused
                  ? context.theme.colors.primary
                  : context.theme.colors.mutedForeground,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stackAmount)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '$direction $target',
                            style: context.theme.typography.body.sm,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        amount,
                      ],
                    )
                  else
                    Text(
                      '$direction $target',
                      style: context.theme.typography.body.sm,
                    ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    _stateLabel(l10n, item.state),
                    style: context.captionStyle,
                  ),
                  if (focused)
                    if (item.issue case final issue?) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        issue.userMessage(l10n),
                        style: context.captionStyle.copyWith(
                          color:
                              issue.recoveryAction ==
                                  RebalanceRecoveryAction.none
                              ? context.theme.colors.destructive
                              : context.theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  AnimatedSizeFade(
                    visible: focused,
                    alignment: AlignmentDirectional.topStart,
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s8),
                      child: Wrap(
                        spacing: AppSpacing.s6,
                        runSpacing: AppSpacing.s6,
                        children: [
                          if (canReview)
                            AppActionButton(
                              variant: FButtonVariant.outline,
                              mainAxisSize: MainAxisSize.min,
                              onPress: busy ? null : onReview,
                              child: Flexible(
                                child: Text(
                                  canEnterManualPrice
                                      ? l10n.rebalanceExecutionAddPriceAction
                                      : l10n.rebalanceExecutionReviewAction,
                                ),
                              ),
                            ),
                          if (canSkip)
                            AppActionButton(
                              variant: FButtonVariant.ghost,
                              mainAxisSize: MainAxisSize.min,
                              onPress: busy ? null : onSkip,
                              child: Flexible(
                                child: Text(l10n.rebalanceExecutionSkipAction),
                              ),
                            ),
                          if (skipped)
                            AppActionButton(
                              variant: FButtonVariant.outline,
                              mainAxisSize: MainAxisSize.min,
                              onPress: busy ? null : onReopen,
                              child: Flexible(
                                child: Text(
                                  l10n.rebalanceExecutionReopenAction,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!stackAmount) ...[const SizedBox(width: AppSpacing.s8), amount],
          ],
        ),
      ),
    );
  }
}

String _stateLabel(
  AppLocalizations l10n,
  RebalanceExecutionItemState state,
) => switch (state) {
  RebalanceExecutionItemState.needsDetails =>
    l10n.rebalanceExecutionStateNeedsDetails,
  RebalanceExecutionItemState.ready => l10n.rebalanceExecutionStateReady,
  RebalanceExecutionItemState.applying => l10n.rebalanceExecutionStateApplying,
  RebalanceExecutionItemState.applied => l10n.rebalanceExecutionStateApplied,
  RebalanceExecutionItemState.applyFailed =>
    l10n.rebalanceExecutionStateApplyFailed,
  RebalanceExecutionItemState.undoing => l10n.rebalanceExecutionStateUndoing,
  RebalanceExecutionItemState.undone => l10n.rebalanceExecutionStateUndone,
  RebalanceExecutionItemState.undoFailed =>
    l10n.rebalanceExecutionStateUndoFailed,
  RebalanceExecutionItemState.skipped => l10n.rebalanceExecutionStateSkipped,
  RebalanceExecutionItemState.recoveryBlocked =>
    l10n.rebalanceExecutionStateRecoveryBlocked,
};
