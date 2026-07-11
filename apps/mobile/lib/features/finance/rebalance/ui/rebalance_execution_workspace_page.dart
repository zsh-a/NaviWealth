import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/home/ui/asset_category_visuals.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../core/shell/master_detail_layout.dart';
import '../../../../core/shortcuts/keyboard_platform.dart';
import '../../../../core/shortcuts/master_detail_shortcuts.dart';
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
  final List<String> _selectedIds = [];
  final FocusNode _masterFocus = FocusNode(debugLabel: 'rebalance master');
  String? _focusedId;

  @override
  void dispose() {
    _masterFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sessionAsync = ref.watch(
      rebalanceExecutionSessionProvider(widget.sessionId),
    );
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
      child: sessionAsync.when(
        loading: () => _WorkspaceStatePage(
          title: l10n.rebalanceExecutionWorkspaceTitle,
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => _WorkspaceStatePage(
          title: l10n.rebalanceExecutionWorkspaceTitle,
          child: _WorkspaceError(
            message: userSafeErrorMessage(
              context,
              error,
              stackTrace: stackTrace,
              operation: 'load rebalance execution workspace',
            ),
            onRetry: _refresh,
          ),
        ),
        data: (session) => session == null
            ? _WorkspaceStatePage(
                title: l10n.rebalanceExecutionWorkspaceTitle,
                child: _WorkspaceError(
                  message: l10n.rebalanceExecutionNotFound,
                  onRetry: _refresh,
                ),
              )
            : _buildSession(session),
      ),
    );
  }

  Widget _buildSession(RebalanceExecutionSession session) {
    final useMasterDetail = MasterDetailLayout.shouldUseMasterDetail(
      MediaQuery.sizeOf(context).width,
    );
    _schedulePrune(session, ensureWideFocus: useMasterDetail);
    final body = _WorkspaceBody(
      session: session,
      selectedIds: _selectedIds,
      focusedId: _focusedId,
      busy: _busy,
      batchRunning: _stopSignal != null,
      onArchive: _archive,
      onReview: _review,
      onSkip: (item) => _mutate((gateway) => gateway.skip(item.id)),
      onReopen: (item) => _mutate((gateway) => gateway.reopen(item.id)),
      onApply: () => _runBatch(undo: false),
      onUndo: () => _runBatch(undo: true),
      onStop: _stop,
      onSelectionChanged: _toggleSelection,
      onFocus: _focusItem,
      onApplySelected: () =>
          _runBatch(undo: false, itemIds: List<String>.of(_selectedIds)),
      onUndoSelected: () =>
          _runBatch(undo: true, itemIds: List<String>.of(_selectedIds)),
      onSkipSelected: () => _mutateSelected(reopen: false),
      onReopenSelected: () => _mutateSelected(reopen: true),
    );
    return Focus(
      focusNode: _masterFocus,
      onKeyEvent: (_, event) => _onMasterKey(session, event),
      child: MasterDetailShortcuts(
        onSelectNext: () => _moveFocus(session, 1),
        onSelectPrevious: () => _moveFocus(session, -1),
        child: body,
      ),
    );
  }

  void _schedulePrune(
    RebalanceExecutionSession session, {
    required bool ensureWideFocus,
  }) {
    final ids = session.items.map((item) => item.id).toSet();
    final now = DateTime.now().toUtc();
    final selectableIds =
        session.status == RebalanceExecutionSessionStatus.active
        ? session.items
              .where((item) => _WorkspaceBody._isSelectable(item, now))
              .map((item) => item.id)
              .toSet()
        : <String>{};
    final focusIsValid = ids.contains(_focusedId);
    final fallbackFocusId = ensureWideFocus
        ? _preferredFocusId(session, selectableIds)
        : null;
    if (_selectedIds.every(selectableIds.contains) &&
        (focusIsValid || _focusedId == fallbackFocusId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedIds.retainWhere(selectableIds.contains);
        if (!ids.contains(_focusedId)) {
          _focusedId = fallbackFocusId;
        }
      });
    });
  }

  static String? _preferredFocusId(
    RebalanceExecutionSession session,
    Set<String> selectableIds,
  ) {
    if (session.items.isEmpty) return null;
    for (final item in session.items) {
      if (selectableIds.contains(item.id)) return item.id;
    }
    return session.items.first.id;
  }

  void _focusItem(String itemId) {
    if (_busy) return;
    setState(() => _focusedId = itemId);
    _masterFocus.requestFocus();
  }

  void _moveFocus(RebalanceExecutionSession session, int delta) {
    if (_busy || isTextInputFocused()) return;
    final items = session.items;
    if (items.isEmpty) return;
    final current = items.indexWhere((item) => item.id == _focusedId);
    final next = current < 0
        ? (delta > 0 ? 0 : items.length - 1)
        : (current + delta).clamp(0, items.length - 1);
    _focusItem(items[next].id);
  }

  KeyEventResult _onMasterKey(
    RebalanceExecutionSession session,
    KeyEvent event,
  ) {
    if (!_masterFocus.hasPrimaryFocus || _busy || isTextInputFocused()) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveFocus(session, 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveFocus(session, -1);
      return KeyEventResult.handled;
    }
    final item = session.items
        .where((candidate) => candidate.id == _focusedId)
        .firstOrNull;
    if (item == null) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final now = DateTime.now().toUtc();
      if (_WorkspaceBody._isSelectable(item, now)) {
        _toggleSelection(item.id, !_selectedIds.contains(item.id));
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      unawaited(_review(item));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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

  Future<void> _runBatch({required bool undo, List<String>? itemIds}) async {
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
          ? await gateway.undo(widget.sessionId, itemIds: itemIds, stop: stop)
          : await gateway.apply(widget.sessionId, itemIds: itemIds, stop: stop);
      if (itemIds != null && mounted) {
        final completed = result.completedItemIds.toSet();
        setState(() {
          _selectedIds.removeWhere(completed.contains);
        });
      }
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

  void _toggleSelection(String itemId, bool selected) {
    if (_busy) return;
    setState(() {
      _selectedIds.remove(itemId);
      if (selected) _selectedIds.add(itemId);
    });
  }

  Future<void> _mutateSelected({required bool reopen}) async {
    if (_busy || _selectedIds.isEmpty) return;
    final before = List<String>.of(_selectedIds);
    final succeeded = <String>[];
    setState(() => _busy = true);
    try {
      final gateway = await ref.read(
        rebalanceExecutionWorkspaceGatewayProvider.future,
      );
      for (final itemId in before) {
        try {
          if (reopen) {
            await gateway.reopen(itemId);
          } else {
            await gateway.skip(itemId);
          }
          succeeded.add(itemId);
        } catch (_) {
          // Per-item outcomes are intentional: later selected rows continue.
        }
      }
      if (mounted) {
        final failed = before.length - succeeded.length;
        setState(() {
          final completed = succeeded.toSet();
          _selectedIds.removeWhere(completed.contains);
        });
        if (failed > 0) {
          AppMessenger.show(
            context,
            ToastKind.warning,
            AppLocalizations.of(
              context,
            ).rebalanceExecutionPartialToast(succeeded.length, failed),
          );
        }
        _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
    if (MasterDetailLayout.shouldUseMasterDetail(
      MediaQuery.sizeOf(context).width,
    )) {
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
                          SoftCard(
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
                    child: SoftCard(
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

class _ExecutionProgress extends StatelessWidget {
  const _ExecutionProgress({
    super.key,
    required this.resolved,
    required this.total,
    required this.driftAfterPct,
  });

  final int resolved;
  final int total;
  final double driftAfterPct;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceExecutionProgress(resolved, total),
                    style: context.theme.typography.body.sm,
                  ),
                ),
                Text(
                  '${(driftAfterPct * 100).toStringAsFixed(1)}%',
                  style: context.captionLabelStyle,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            LinearProgressIndicator(value: total == 0 ? 0 : resolved / total),
          ],
        ),
      ),
    );
  }
}

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

class _WorkspaceStatePage extends StatelessWidget {
  const _WorkspaceStatePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(title: title, childPad: false, child: child);
  }
}

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
      child: FTappable(
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
    final stackAmount =
        Breakpoints.isMobile(MediaQuery.sizeOf(context).width) &&
        MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final amount = AnimatedMoneyText(
      amount: item.suggestion.amount.amount.toDouble(),
      currencyCode: item.suggestion.amount.currency,
      compact: true,
      showSign: false,
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onFocus,
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
