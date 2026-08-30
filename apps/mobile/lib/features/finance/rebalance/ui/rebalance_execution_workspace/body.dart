part of '../rebalance_execution_workspace_page.dart';

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({
    required this.session,
    required this.selectedIds,
    required this.focusedId,
    required this.busy,
    required this.batchRunning,
    required this.onArchive,
    required this.onReview,
    required this.onSkip,
    required this.onReopen,
    required this.onApply,
    required this.onUndo,
    required this.onStop,
    required this.onSelectionChanged,
    required this.onFocus,
    required this.onApplySelected,
    required this.onUndoSelected,
    required this.onSkipSelected,
    required this.onReopenSelected,
    required this.useMasterDetail,
  });

  final RebalanceExecutionSession session;
  final List<String> selectedIds;
  final String? focusedId;
  final bool busy;
  final bool batchRunning;
  final VoidCallback onArchive;
  final ValueChanged<RebalanceExecutionItem> onReview;
  final ValueChanged<RebalanceExecutionItem> onSkip;
  final ValueChanged<RebalanceExecutionItem> onReopen;
  final VoidCallback onApply;
  final VoidCallback onUndo;
  final VoidCallback onStop;
  final void Function(String itemId, bool selected) onSelectionChanged;
  final ValueChanged<String> onFocus;
  final VoidCallback onApplySelected;
  final VoidCallback onUndoSelected;
  final VoidCallback onSkipSelected;
  final VoidCallback onReopenSelected;
  final bool useMasterDetail;

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
    final now = DateTime.now().toUtc();
    final selectedItems = session.items
        .where((item) => selectedIds.contains(item.id))
        .toList(growable: false);
    final hasSelectedApply =
        selectedItems.isNotEmpty &&
        selectedItems.every((item) => _canApplySelected(item, now));
    final hasSelectedUndo =
        selectedItems.isNotEmpty &&
        selectedItems.every((item) => _canUndoSelected(item, now));
    final hasSelectedSkip =
        selectedItems.isNotEmpty && selectedItems.every(_canSkipSelected);
    final hasSelectedReopen =
        selectedItems.isNotEmpty &&
        selectedItems.every(
          (item) => item.state == RebalanceExecutionItemState.skipped,
        );
    final hasInterruptedSelected = selectedItems.any(
      (item) =>
          (item.state == RebalanceExecutionItemState.applying ||
              item.state == RebalanceExecutionItemState.undoing) &&
          item.leaseUntil != null &&
          !item.leaseUntil!.isAfter(now),
    );
    final progress = _ExecutionProgress(
      key: const Key('rebalance-execution-progress'),
      resolved: resolved,
      total: session.items.length,
      driftAfterPct: session.plan.driftAfterPct,
    );
    final showFooter = mutable && (batchRunning || ready || applied);
    if (useMasterDetail) {
      final focusedItem = session.items
          .where((item) => item.id == focusedId)
          .firstOrNull;
      final footer = mutable && selectedItems.isNotEmpty
          ? _ExecutionSelectionActions(
              count: selectedItems.length,
              busy: busy,
              canApply: hasSelectedApply,
              canUndo: hasSelectedUndo,
              canSkip: hasSelectedSkip,
              canReopen: hasSelectedReopen,
              resumeInterrupted: hasInterruptedSelected,
              onApply: onApplySelected,
              onUndo: onUndoSelected,
              onSkip: onSkipSelected,
              onReopen: onReopenSelected,
            )
          : showFooter
          ? _ExecutionAggregateActions(
              busy: busy,
              batchRunning: batchRunning,
              canApply: ready,
              retryApply: retryApply,
              canUndo: applied,
              retryUndo: retryUndo,
              onApply: onApply,
              onUndo: onUndo,
              onStop: onStop,
            )
          : null;
      return AppPageScaffold(
        title: l10n.rebalanceExecutionWorkspaceTitle,
        actions: mutable
            ? [
                AppHeaderAction(
                  icon: const Icon(FLucideIcons.archive),
                  semanticsLabel: l10n.rebalanceExecutionArchiveAction,
                  onPress: busy ? null : onArchive,
                ),
              ]
            : const <Widget>[],
        child: Column(
          children: [
            Expanded(
              child: MasterDetailLayout(
                master: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.s12),
                      child: progress,
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.s12,
                          0,
                          AppSpacing.s12,
                          AppSpacing.s12,
                        ),
                        itemCount: session.items.length,
                        itemBuilder: (context, index) {
                          final item = session.items[index];
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.s8,
                            ),
                            child: _ExecutionMasterRow(
                              item: item,
                              selected: selectedIds.contains(item.id),
                              focused: focusedId == item.id,
                              selectable: mutable && _isSelectable(item, now),
                              busy: busy,
                              onSelectionChanged: (selected) =>
                                  onSelectionChanged(item.id, selected),
                              onFocus: () => onFocus(item.id),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                detail: focusedItem == null
                    ? MasterDetailEmpty(
                        message: l10n.rebalanceExecutionReviewAction,
                        icon: FLucideIcons.listChecks,
                      )
                    : ListView(
                        padding: const EdgeInsets.all(AppSpacing.s24),
                        children: [
                          SoftCard.raised(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s16,
                              ),
                              child: _ExecutionItemRow(
                                item: focusedItem,
                                selected: selectedIds.contains(focusedItem.id),
                                focused: true,
                                showSelection: false,
                                selectable:
                                    mutable && _isSelectable(focusedItem, now),
                                mutable: mutable,
                                busy: busy,
                                onReview: () => onReview(focusedItem),
                                onSkip: () => onSkip(focusedItem),
                                onReopen: () => onReopen(focusedItem),
                                onSelectionChanged: (selected) =>
                                    onSelectionChanged(
                                      focusedItem.id,
                                      selected,
                                    ),
                                onFocus: () => onFocus(focusedItem.id),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            if (footer != null)
              AppFormActionBar(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s24,
                  ),
                  child: footer,
                ),
              ),
          ],
        ),
      );
    }
    return AppTaskScaffold(
      title: l10n.rebalanceExecutionWorkspaceTitle,
      actionsBuilder: (_, _) => mutable
          ? [
              AppHeaderAction(
                icon: const Icon(FLucideIcons.archive),
                semanticsLabel: l10n.rebalanceExecutionArchiveAction,
                onPress: busy ? null : onArchive,
              ),
            ]
          : const <Widget>[],
      compactLeadingSliversBuilder: (_) => [
        SliverToBoxAdapter(child: progress),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s12)),
      ],
      railBuilder: (_) => progress,
      primarySliversBuilder: (_) => session.items.isEmpty
          ? [
              SliverFillRemaining(
                hasScrollBody: false,
                child: AppEmptyState(
                  icon: FLucideIcons.listChecks,
                  title: l10n.rebalanceExecutionEmptyQueue,
                  action: FButton(
                    variant: FButtonVariant.outline,
                    onPress: () => smartPop(context),
                    child: Text(l10n.commonClose),
                  ),
                ),
              ),
            ]
          : [
              SliverList.builder(
                itemCount: session.items.length,
                itemBuilder: (context, index) {
                  final item = session.items[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == session.items.length - 1
                          ? AppSpacing.s12
                          : AppSpacing.s8,
                    ),
                    child: SoftCard.raised(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s12,
                        ),
                        child: _ExecutionItemRow(
                          item: item,
                          selected: selectedIds.contains(item.id),
                          focused: focusedId == item.id,
                          selectable: mutable && _isSelectable(item, now),
                          mutable: mutable,
                          busy: busy,
                          onReview: () => onReview(item),
                          onSkip: () => onSkip(item),
                          onReopen: () => onReopen(item),
                          onSelectionChanged: (selected) =>
                              onSelectionChanged(item.id, selected),
                          onFocus: () => onFocus(item.id),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
      footerBuilder: mutable && selectedItems.isNotEmpty
          ? (_) => _ExecutionSelectionActions(
              count: selectedItems.length,
              busy: busy,
              canApply: hasSelectedApply,
              canUndo: hasSelectedUndo,
              canSkip: hasSelectedSkip,
              canReopen: hasSelectedReopen,
              resumeInterrupted: hasInterruptedSelected,
              onApply: onApplySelected,
              onUndo: onUndoSelected,
              onSkip: onSkipSelected,
              onReopen: onReopenSelected,
            )
          : showFooter
          ? (_) => _ExecutionAggregateActions(
              busy: busy,
              batchRunning: batchRunning,
              canApply: ready,
              retryApply: retryApply,
              canUndo: applied,
              retryUndo: retryUndo,
              onApply: onApply,
              onUndo: onUndo,
              onStop: onStop,
            )
          : null,
    );
  }

  static bool _isSelectable(RebalanceExecutionItem item, DateTime now) {
    if (item.state == RebalanceExecutionItemState.recoveryBlocked ||
        item.state == RebalanceExecutionItemState.undone) {
      return false;
    }
    if (item.state == RebalanceExecutionItemState.undoFailed &&
        item.issue?.recoveryAction != RebalanceRecoveryAction.retryUndo) {
      return false;
    }
    if (item.state == RebalanceExecutionItemState.applying ||
        item.state == RebalanceExecutionItemState.undoing) {
      return item.leaseUntil != null && !item.leaseUntil!.isAfter(now);
    }
    return true;
  }

  static bool _canApplySelected(RebalanceExecutionItem item, DateTime now) =>
      item.state == RebalanceExecutionItemState.ready ||
      (item.state == RebalanceExecutionItemState.applyFailed &&
          item.issue?.recoveryAction == RebalanceRecoveryAction.retryApply) ||
      (item.state == RebalanceExecutionItemState.applying &&
          item.leaseUntil != null &&
          !item.leaseUntil!.isAfter(now));

  static bool _canUndoSelected(RebalanceExecutionItem item, DateTime now) =>
      item.state == RebalanceExecutionItemState.applied ||
      (item.state == RebalanceExecutionItemState.undoFailed &&
          item.issue?.recoveryAction == RebalanceRecoveryAction.retryUndo) ||
      (item.state == RebalanceExecutionItemState.undoing &&
          item.leaseUntil != null &&
          !item.leaseUntil!.isAfter(now));

  static bool _canSkipSelected(RebalanceExecutionItem item) => const {
    RebalanceExecutionItemState.needsDetails,
    RebalanceExecutionItemState.ready,
    RebalanceExecutionItemState.applyFailed,
  }.contains(item.state);
}
