import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/home/ui/asset_category_visuals.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../application/rebalance_execution_coordinator.dart';
import '../application/rebalance_execution_workspace_gateway.dart';
import '../data/rebalance_providers.dart';
import '../domain/rebalance_execution.dart';
import 'rebalance_execution_issue_presentation.dart';
import 'rebalance_execution_review_sheet.dart';

class RebalanceExecutionWorkspacePage extends ConsumerStatefulWidget {
  const RebalanceExecutionWorkspacePage({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<RebalanceExecutionWorkspacePage> createState() =>
      _RebalanceExecutionWorkspacePageState();
}

class _RebalanceExecutionWorkspacePageState
    extends ConsumerState<RebalanceExecutionWorkspacePage> {
  bool _busy = false;
  MutableRebalanceStopSignal? _stopSignal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sessionAsync = ref.watch(
      rebalanceExecutionSessionProvider(widget.sessionId),
    );
    final session = sessionAsync.value;
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _busy) {
          AppMessenger.show(
            context,
            ToastKind.warning,
            l10n.rebalanceExecutionBusyLeaveBlocked,
          );
        }
      },
      child: AppPageScaffold(
        title: l10n.rebalanceExecutionWorkspaceTitle,
        actions: [
          if (session?.status == RebalanceExecutionSessionStatus.active)
            AppHeaderAction(
              icon: const Icon(FLucideIcons.archive),
              semanticsLabel: l10n.rebalanceExecutionArchiveAction,
              onPress: _busy ? null : _archive,
            ),
        ],
        childPad: false,
        child: sessionAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _WorkspaceError(
            message: userSafeErrorMessage(
              context,
              error,
              stackTrace: stackTrace,
              operation: 'load rebalance execution workspace',
            ),
            onRetry: _refresh,
          ),
          data: (session) => session == null
              ? _WorkspaceError(
                  message: l10n.rebalanceExecutionNotFound,
                  onRetry: _refresh,
                )
              : _WorkspaceBody(
                  session: session,
                  busy: _busy,
                  batchRunning: _stopSignal != null,
                  onReview: _review,
                  onSkip: (item) => _mutate((gateway) => gateway.skip(item.id)),
                  onReopen: (item) =>
                      _mutate((gateway) => gateway.reopen(item.id)),
                  onApply: () => _runBatch(undo: false),
                  onUndo: () => _runBatch(undo: true),
                  onStop: _stop,
                ),
        ),
      ),
    );
  }

  Future<void> _review(RebalanceExecutionItem item) async {
    if (_busy) return;
    final saved = await showRebalanceExecutionReviewSheet(
      context: context,
      item: item,
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _archive() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    try {
      final gateway = await ref.read(
        rebalanceExecutionWorkspaceGatewayProvider.future,
      );
      final fresh = await gateway.session(widget.sessionId);
      if (!mounted ||
          fresh == null ||
          fresh.status != RebalanceExecutionSessionStatus.active) {
        _refresh();
        return;
      }
      final hasApplied = fresh.items.any((item) => item.isEconomicallyApplied);
      final confirmed = await showConfirmDialog(
        context: context,
        title: Text(l10n.rebalanceExecutionArchiveTitle),
        body: Text(
          hasApplied
              ? '${l10n.rebalanceExecutionArchiveBody}\n\n'
                    '${l10n.rebalanceExecutionArchiveAppliedBody}'
              : l10n.rebalanceExecutionArchiveBody,
        ),
        cancelLabel: l10n.commonCancel,
        confirmLabel: l10n.rebalanceExecutionArchiveAction,
        icon: FLucideIcons.archive,
      );
      if (confirmed != true || !mounted) return;
      setState(() => _busy = true);
      await gateway.archive(widget.sessionId);
      ref.invalidate(activeRebalanceExecutionProvider);
      if (mounted) context.go(FinanceRoutes.planRebalance);
    } catch (error, stackTrace) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          userSafeErrorMessage(
            context,
            error,
            stackTrace: stackTrace,
            operation: 'archive rebalance execution',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runBatch({required bool undo}) async {
    if (_busy) {
      _stop();
      return;
    }
    final stop = MutableRebalanceStopSignal();
    setState(() {
      _busy = true;
      _stopSignal = stop;
    });
    try {
      final gateway = await ref.read(
        rebalanceExecutionWorkspaceGatewayProvider.future,
      );
      final result = undo
          ? await gateway.undo(widget.sessionId, stop: stop)
          : await gateway.apply(widget.sessionId, stop: stop);
      if (mounted) _showBatchResult(result);
      if (mounted) _refresh();
    } catch (error, stackTrace) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          userSafeErrorMessage(
            context,
            error,
            stackTrace: stackTrace,
            operation: undo
                ? 'undo rebalance execution'
                : 'apply rebalance execution',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stopSignal = null;
        });
      }
    }
  }

  void _stop() => _stopSignal?.stop();

  void _showBatchResult(RebalanceExecutionBatchResult result) {
    final l10n = AppLocalizations.of(context);
    if (result.stopped &&
        result.failures.every(
          (failure) => failure.code == RebalanceExecutionFailureCode.stopped,
        )) {
      AppMessenger.show(
        context,
        ToastKind.warning,
        l10n.rebalanceExecutionStoppedToast,
      );
      return;
    }
    if (result.failures.any(
      (failure) =>
          failure.code == RebalanceExecutionFailureCode.recoveryBlocked,
    )) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.rebalanceExecutionRecoveryToast,
      );
      return;
    }
    if (result.failures.isNotEmpty) {
      final completed = result.completedItemIds.length;
      final singleIssue = completed == 0 && result.failures.length == 1
          ? result.failures.single.issue
          : null;
      AppMessenger.show(
        context,
        _batchFailureToastKind(result.failures),
        singleIssue?.userMessage(l10n) ??
            (completed == 0
                ? l10n.rebalanceExecutionFailedToast(result.failures.length)
                : l10n.rebalanceExecutionPartialToast(
                    completed,
                    result.failures.length,
                  )),
      );
      return;
    }
    AppMessenger.show(
      context,
      ToastKind.success,
      l10n.rebalanceExecutionCompletedToast,
    );
  }

  Future<void> _mutate(
    Future<Object?> Function(RebalanceExecutionWorkspaceGateway gateway) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final gateway = await ref.read(
        rebalanceExecutionWorkspaceGatewayProvider.future,
      );
      await action(gateway);
      if (mounted) _refresh();
    } catch (error, stackTrace) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          userSafeErrorMessage(
            context,
            error,
            stackTrace: stackTrace,
            operation: 'mutate rebalance execution item',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refresh() {
    ref
      ..invalidate(rebalanceExecutionSessionProvider(widget.sessionId))
      ..invalidate(activeRebalanceExecutionProvider);
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({
    required this.session,
    required this.busy,
    required this.batchRunning,
    required this.onReview,
    required this.onSkip,
    required this.onReopen,
    required this.onApply,
    required this.onUndo,
    required this.onStop,
  });

  final RebalanceExecutionSession session;
  final bool busy;
  final bool batchRunning;
  final ValueChanged<RebalanceExecutionItem> onReview;
  final ValueChanged<RebalanceExecutionItem> onSkip;
  final ValueChanged<RebalanceExecutionItem> onReopen;
  final VoidCallback onApply;
  final VoidCallback onUndo;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resolved = session.items.where((item) => item.isResolved).length;
    final retryApply = session.items.any(
      (item) =>
          item.issue?.recoveryAction == RebalanceRecoveryAction.retryApply,
    );
    final ready =
        retryApply ||
        session.items.any(
          (item) => item.state == RebalanceExecutionItemState.ready,
        );
    final retryUndo = session.items.any(
      (item) => item.issue?.recoveryAction == RebalanceRecoveryAction.retryUndo,
    );
    final applied = session.items.any((item) => item.isEconomicallyApplied);
    final mutable = session.status == RebalanceExecutionSessionStatus.active;
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = Breakpoints.isMobile(constraints.maxWidth)
            ? const EdgeInsets.all(AppSpacing.s16)
            : const EdgeInsets.all(AppSpacing.s24);
        return ListView(
          padding: padding,
          children: [
            SoftCard(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.rebalanceExecutionProgress(
                              resolved,
                              session.items.length,
                            ),
                            style: context.theme.typography.body.sm,
                          ),
                        ),
                        Text(
                          '${(session.plan.driftAfterPct * 100).toStringAsFixed(1)}%',
                          style: context.captionLabelStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    LinearProgressIndicator(
                      value: session.items.isEmpty
                          ? 0
                          : resolved / session.items.length,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    if (mutable)
                      Wrap(
                        spacing: AppSpacing.s8,
                        runSpacing: AppSpacing.s8,
                        children: [
                          if (batchRunning)
                            AppActionButton(
                              variant: FButtonVariant.destructive,
                              mainAxisSize: MainAxisSize.min,
                              onPress: onStop,
                              child: Flexible(
                                child: Text(
                                  l10n.rebalanceExecutionStopAction,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else ...[
                            AppActionButton(
                              mainAxisSize: MainAxisSize.min,
                              onPress: busy || !ready ? null : onApply,
                              child: Flexible(
                                child: Text(
                                  retryApply
                                      ? l10n.rebalanceExecutionRetryApplyAction
                                      : l10n.rebalanceExecutionApplyAction,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            AppActionButton(
                              variant: FButtonVariant.outline,
                              mainAxisSize: MainAxisSize.min,
                              onPress: busy || !applied ? null : onUndo,
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
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            if (session.items.isEmpty)
              AppEmptyState(
                icon: FLucideIcons.listChecks,
                title: l10n.rebalanceExecutionEmptyQueue,
              )
            else
              SoftCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s12,
                  ),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < session.items.length;
                        index++
                      ) ...[
                        if (index > 0) const FDivider(),
                        _ExecutionItemRow(
                          item: session.items[index],
                          mutable: mutable,
                          busy: busy,
                          onReview: () => onReview(session.items[index]),
                          onSkip: () => onSkip(session.items[index]),
                          onReopen: () => onReopen(session.items[index]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ExecutionItemRow extends StatelessWidget {
  const _ExecutionItemRow({
    required this.item,
    required this.mutable,
    required this.busy,
    required this.onReview,
    required this.onSkip,
    required this.onReopen,
  });

  final RebalanceExecutionItem item;
  final bool mutable;
  final bool busy;
  final VoidCallback onReview;
  final VoidCallback onSkip;
  final VoidCallback onReopen;

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
    final stackAmount =
        Breakpoints.isMobile(MediaQuery.sizeOf(context).width) &&
        MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final amount = AnimatedMoneyText(
      amount: item.suggestion.amount.amount.toDouble(),
      currencyCode: item.suggestion.amount.currency,
      compact: true,
      showSign: false,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            AssetCategoryVisuals.icon(item.suggestion.category),
            size: AppIconSizes.h18,
            color: context.theme.colors.mutedForeground,
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
                if (item.issue case final issue?) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    issue.userMessage(l10n),
                    style: context.captionStyle.copyWith(
                      color:
                          issue.recoveryAction == RebalanceRecoveryAction.none
                          ? context.theme.colors.destructive
                          : context.theme.colors.mutedForeground,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.s8),
                Wrap(
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
                          child: Text(l10n.rebalanceExecutionReopenAction),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (!stackAmount) ...[const SizedBox(width: AppSpacing.s8), amount],
        ],
      ),
    );
  }
}

class _WorkspaceError extends StatelessWidget {
  const _WorkspaceError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: FLucideIcons.triangleAlert,
      title: message,
      action: AppActionButton(
        variant: FButtonVariant.outline,
        onPress: onRetry,
        child: Text(AppLocalizations.of(context).commonRetry),
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

ToastKind _batchFailureToastKind(List<RebalanceExecutionFailure> failures) {
  for (final failure in failures) {
    if (failure.code == RebalanceExecutionFailureCode.stopped) continue;
    final issue = failure.issue;
    if (issue == null || issue.recoveryAction == RebalanceRecoveryAction.none) {
      return ToastKind.error;
    }
  }
  return ToastKind.warning;
}
