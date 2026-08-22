part of '../rebalance_execution_workspace_page.dart';

class _ExecutionAggregateActions extends StatelessWidget {
  const _ExecutionAggregateActions({
    required this.busy,
    required this.batchRunning,
    required this.canApply,
    required this.retryApply,
    required this.canUndo,
    required this.retryUndo,
    required this.onApply,
    required this.onUndo,
    required this.onStop,
  });

  final bool busy;
  final bool batchRunning;
  final bool canApply;
  final bool retryApply;
  final bool canUndo;
  final bool retryUndo;
  final VoidCallback onApply;
  final VoidCallback onUndo;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (batchRunning) {
      return AppActionButton(
        variant: FButtonVariant.destructive,
        onPress: onStop,
        child: Text(l10n.rebalanceExecutionStopAction),
      );
    }
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        if (canApply)
          AppActionButton(
            mainAxisSize: MainAxisSize.min,
            onPress: busy ? null : onApply,
            child: Flexible(
              child: Text(
                retryApply
                    ? l10n.rebalanceExecutionRetryApplyAction
                    : l10n.rebalanceExecutionApplyAction,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (canUndo)
          AppActionButton(
            variant: FButtonVariant.outline,
            mainAxisSize: MainAxisSize.min,
            onPress: busy ? null : onUndo,
            child: Flexible(
              child: Text(
                retryUndo
                    ? l10n.rebalanceExecutionRetryUndoAction
                    : l10n.rebalanceExecutionUndoAction,
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class _ExecutionSelectionActions extends StatelessWidget {
  const _ExecutionSelectionActions({
    required this.count,
    required this.busy,
    required this.canApply,
    required this.canUndo,
    required this.canSkip,
    required this.canReopen,
    required this.resumeInterrupted,
    required this.onApply,
    required this.onUndo,
    required this.onSkip,
    required this.onReopen,
  });

  final int count;
  final bool busy;
  final bool canApply;
  final bool canUndo;
  final bool canSkip;
  final bool canReopen;
  final bool resumeInterrupted;
  final VoidCallback onApply;
  final VoidCallback onUndo;
  final VoidCallback onSkip;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Text(l10n.commonSelectedCount(count), style: context.labelStyle),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (canApply)
                  AppActionButton(
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : onApply,
                    child: Text(
                      resumeInterrupted
                          ? l10n.rebalanceExecutionResumeInterruptedAction
                          : l10n.rebalanceExecutionApplyAction,
                    ),
                  ),
                if (canUndo) ...[
                  const SizedBox(width: AppSpacing.s8),
                  AppActionButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : onUndo,
                    child: Text(
                      resumeInterrupted
                          ? l10n.rebalanceExecutionResumeInterruptedAction
                          : l10n.rebalanceExecutionUndoAction,
                    ),
                  ),
                ],
                if (canSkip) ...[
                  const SizedBox(width: AppSpacing.s8),
                  AppActionButton(
                    variant: FButtonVariant.ghost,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : onSkip,
                    child: Text(l10n.rebalanceExecutionSkipAction),
                  ),
                ],
                if (canReopen) ...[
                  const SizedBox(width: AppSpacing.s8),
                  AppActionButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : onReopen,
                    child: Text(l10n.rebalanceExecutionReopenAction),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
