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

import '../../../../core/format/formatters.dart';
import '../../../../core/shell/master_detail_layout.dart';
import '../../../../core/shortcuts/keyboard_platform.dart';
import '../../../../core/shortcuts/master_detail_shortcuts.dart';
import '../application/rebalance_execution_coordinator.dart';
import '../application/rebalance_execution_workspace_gateway.dart';
import '../data/rebalance_providers.dart';
import '../domain/rebalance_execution.dart';
import 'rebalance_execution_issue_presentation.dart';
import 'rebalance_execution_review_sheet.dart';

part 'rebalance_execution_workspace/actions.dart';
part 'rebalance_execution_workspace/body.dart';
part 'rebalance_execution_workspace/progress.dart';
part 'rebalance_execution_workspace/rows.dart';
part 'rebalance_execution_workspace/state_pages.dart';

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
      child: LayoutBuilder(
        builder: (context, constraints) => sessionAsync.when(
          loading: () => _WorkspaceStatePage(
            title: l10n.rebalanceExecutionWorkspaceTitle,
            child: const Center(child: FCircularProgress()),
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
              : _buildSession(session, constraints.maxWidth),
        ),
      ),
    );
  }

  Widget _buildSession(
    RebalanceExecutionSession session,
    double availableWidth,
  ) {
    final useMasterDetail = MasterDetailLayout.shouldUseMasterDetail(
      availableWidth,
    );
    _schedulePrune(session, ensureFocus: true);
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
      useMasterDetail: useMasterDetail,
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
    required bool ensureFocus,
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
    final fallbackFocusId = ensureFocus
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
            AppLocalizations.of(context)
                .rebalanceExecutionPartialToast(succeeded.length, failed),
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
