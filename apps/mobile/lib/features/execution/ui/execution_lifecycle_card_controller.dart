import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/execution_repository.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_widgets.dart';

class ExecutionPlanCardController extends ConsumerStatefulWidget {
  const ExecutionPlanCardController({
    super.key,
    required this.plan,
    required this.onCreateAction,
    required this.onEdit,
    required this.onRecordProgress,
    this.openActionCount,
    this.blockedActionCount,
    this.onOpen,
    this.showActions = true,
    this.showTypeLabel = false,
  });

  final ExecutionPlan plan;
  final VoidCallback onCreateAction;
  final VoidCallback onEdit;
  final VoidCallback onRecordProgress;
  final int? openActionCount;
  final int? blockedActionCount;
  final VoidCallback? onOpen;
  final bool showActions;
  final bool showTypeLabel;

  @override
  ConsumerState<ExecutionPlanCardController> createState() =>
      _ExecutionPlanCardControllerState();
}

class _ExecutionPlanCardControllerState
    extends ConsumerState<ExecutionPlanCardController> {
  bool _busy = false;

  Future<void> _changeStatus(ExecutionPlanStatus status) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final feedbackContext = context;
    AppMessenger.cacheOverlay(feedbackContext);
    if ((status == ExecutionPlanStatus.completed ||
            status == ExecutionPlanStatus.archived) &&
        !await _confirmOpenActions(
          context,
          widget.openActionCount ?? 0,
          archive: status == ExecutionPlanStatus.archived,
        )) {
      return;
    }
    if (!feedbackContext.mounted || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(ref);
      final progress = ExecutionProgressEntry(
        id: kExecutionUuid.v4(),
        planId: widget.plan.id,
        kind: _planProgressKind(status),
        note: _planProgressNote(l10n, status),
        createdAt: sync.updatedAt,
        sync: sync,
      );
      final affectedActions = await repo.updatePlanStatus(
        plan: widget.plan,
        status: status,
        sync: sync,
        progress: progress,
      );
      final undo = ExecutionPlanStatusUndo(
        repository: repo,
        before: widget.plan,
        affectedActions: affectedActions,
        appliedSync: sync,
        stamp: () => _stampForUndo(ref),
        progressId: progress.id,
      );
      if (feedbackContext.mounted) {
        AppMessenger.show(
          feedbackContext,
          ToastKind.success,
          l10n.executionLifecycleStatusUpdated(
            executionPlanStatusLabel(l10n, status),
          ),
          duration: const Duration(seconds: 6),
          actionLabel: l10n.commonUndo,
          onAction: () =>
              unawaited(_undoPlanStatus(feedbackContext, undo, l10n)),
        );
      }
    } catch (_) {
      if (feedbackContext.mounted) {
        AppMessenger.show(
          feedbackContext,
          ToastKind.error,
          l10n.executionPlanStatusUpdateFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoPlanStatus(
    BuildContext feedbackContext,
    ExecutionPlanStatusUndo undo,
    AppLocalizations l10n,
  ) async {
    try {
      await undo.restore();
      if (feedbackContext.mounted) {
        AppMessenger.show(
          feedbackContext,
          ToastKind.success,
          l10n.commonUndoSucceeded,
        );
      }
    } on Object {
      if (feedbackContext.mounted) {
        AppMessenger.show(
          feedbackContext,
          ToastKind.error,
          l10n.commonUndoFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExecutionPlanCard(
      plan: widget.plan,
      openActionCount: widget.openActionCount,
      blockedActionCount: widget.blockedActionCount,
      busy: _busy,
      onOpen: _busy ? null : widget.onOpen,
      showActions: widget.showActions,
      showTypeLabel: widget.showTypeLabel,
      onCreateAction: widget.onCreateAction,
      onEdit: widget.onEdit,
      onRecordProgress: widget.onRecordProgress,
      onPause: () => _changeStatus(ExecutionPlanStatus.paused),
      onResume: () => _changeStatus(ExecutionPlanStatus.active),
      onComplete: () => _changeStatus(ExecutionPlanStatus.completed),
      onArchive: () => _changeStatus(ExecutionPlanStatus.archived),
    );
  }
}

Future<bool> _confirmOpenActions(
  BuildContext context,
  int count, {
  required bool archive,
}) async {
  if (count == 0) return true;
  final l10n = AppLocalizations.of(context);
  return await showConfirmDialog(
        context: context,
        title: Text(
          archive
              ? l10n.executionLifecycleArchiveConfirmTitle
              : l10n.executionLifecycleCompleteConfirmTitle,
        ),
        body: Text(
          archive
              ? l10n.executionLifecycleArchiveConfirmBody(count)
              : l10n.executionLifecycleCompleteConfirmBody(count),
        ),
        confirmLabel: archive
            ? l10n.executionLifecycleArchive
            : l10n.executionLifecycleComplete,
        cancelLabel: l10n.commonCancel,
        icon: FLucideIcons.triangleAlert,
      ) ==
      true;
}

Future<SyncMeta> _stampForUndo(WidgetRef ref) async {
  final next = await ref.read(mutationStamperProvider.future);
  final stamp = await next.stamp();
  return SyncMeta(
    ownerUserId: stamp.ownerUserId,
    updatedAt: stamp.now,
    updatedByDevice: stamp.deviceId,
    hlc: stamp.hlc,
  );
}

class ExecutionPlanStatusUndo {
  const ExecutionPlanStatusUndo({
    required this.repository,
    required this.before,
    required this.affectedActions,
    required this.appliedSync,
    required this.stamp,
    required this.progressId,
  });

  final ExecutionRepository repository;
  final ExecutionPlan before;
  final List<ExecutionAction> affectedActions;
  final SyncMeta appliedSync;
  final Future<SyncMeta> Function() stamp;
  final String progressId;

  Future<void> restore() async {
    final current = await repository.findPlan(
      ownerUserId: before.sync.ownerUserId,
      id: before.id,
    );
    if (current == null || current.sync.hlc != appliedSync.hlc) {
      throw StateError('Plan changed after the status update.');
    }
    for (final action in affectedActions) {
      final currentAction = await repository.findAction(
        ownerUserId: before.sync.ownerUserId,
        id: action.id,
      );
      if (currentAction == null || currentAction.sync.hlc != appliedSync.hlc) {
        throw StateError('Action changed after the status update.');
      }
    }
    final sync = await stamp();
    await repository.restorePlanLifecycle(
      plan: before,
      actions: affectedActions,
      progressId: progressId,
      sync: sync,
    );
  }
}

ExecutionProgressKind _planProgressKind(ExecutionPlanStatus status) {
  return switch (status) {
    ExecutionPlanStatus.completed => ExecutionProgressKind.completion,
    ExecutionPlanStatus.paused ||
    ExecutionPlanStatus.archived => ExecutionProgressKind.scopeChange,
    ExecutionPlanStatus.active => ExecutionProgressKind.checkin,
  };
}

String _planProgressNote(AppLocalizations l10n, ExecutionPlanStatus status) {
  return switch (status) {
    ExecutionPlanStatus.paused => l10n.executionPlanPausedDefault,
    ExecutionPlanStatus.active => l10n.executionPlanResumedDefault,
    ExecutionPlanStatus.completed => l10n.executionPlanCompletedDefault,
    ExecutionPlanStatus.archived => l10n.executionPlanArchivedDefault,
  };
}
