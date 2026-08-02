import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_widgets.dart';

class ExecutionProjectCardController extends ConsumerStatefulWidget {
  const ExecutionProjectCardController({
    super.key,
    required this.project,
    required this.onCreateAction,
    required this.onEdit,
    required this.onRecordProgress,
    this.openActionCount,
    this.blockedActionCount,
    this.commitmentCount,
    this.onOpen,
    this.showActions = true,
    this.showTypeLabel = false,
  });

  final ExecutionProject project;
  final VoidCallback onCreateAction;
  final VoidCallback onEdit;
  final VoidCallback onRecordProgress;
  final int? openActionCount;
  final int? blockedActionCount;
  final int? commitmentCount;
  final VoidCallback? onOpen;
  final bool showActions;
  final bool showTypeLabel;

  @override
  ConsumerState<ExecutionProjectCardController> createState() =>
      _ExecutionProjectCardControllerState();
}

class _ExecutionProjectCardControllerState
    extends ConsumerState<ExecutionProjectCardController> {
  bool _busy = false;

  Future<void> _changeStatus(ExecutionProjectStatus status) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    if ((status == ExecutionProjectStatus.completed ||
            status == ExecutionProjectStatus.archived) &&
        !await _confirmOpenActions(
          context,
          widget.openActionCount ?? 0,
          archive: status == ExecutionProjectStatus.archived,
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(ref);
      await repo.updateProjectStatus(
        project: widget.project,
        status: status,
        sync: sync,
        progress: ExecutionProgressEntry(
          id: kExecutionUuid.v4(),
          projectId: widget.project.id,
          kind: _projectProgressKind(status),
          note: _projectProgressNote(l10n, status),
          createdAt: sync.updatedAt,
          sync: sync,
        ),
      );
    } catch (_) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.executionProjectStatusUpdateFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExecutionProjectCard(
      project: widget.project,
      openActionCount: widget.openActionCount,
      blockedActionCount: widget.blockedActionCount,
      commitmentCount: widget.commitmentCount,
      busy: _busy,
      onOpen: _busy ? null : widget.onOpen,
      showActions: widget.showActions,
      showTypeLabel: widget.showTypeLabel,
      onCreateAction: widget.onCreateAction,
      onEdit: widget.onEdit,
      onRecordProgress: widget.onRecordProgress,
      onPause: () => _changeStatus(ExecutionProjectStatus.paused),
      onResume: () => _changeStatus(ExecutionProjectStatus.active),
      onComplete: () => _changeStatus(ExecutionProjectStatus.completed),
      onArchive: () => _changeStatus(ExecutionProjectStatus.archived),
    );
  }
}

class ExecutionCommitmentCardController extends ConsumerStatefulWidget {
  const ExecutionCommitmentCardController({
    super.key,
    required this.commitment,
    required this.onCreateAction,
    required this.onEdit,
    required this.onRecordProgress,
    this.openActionCount,
    this.blockedActionCount,
    this.projectLabel,
    this.onOpen,
    this.showActions = true,
    this.showTypeLabel = false,
  });

  final ExecutionCommitment commitment;
  final VoidCallback onCreateAction;
  final VoidCallback onEdit;
  final VoidCallback onRecordProgress;
  final int? openActionCount;
  final int? blockedActionCount;
  final String? projectLabel;
  final VoidCallback? onOpen;
  final bool showActions;
  final bool showTypeLabel;

  @override
  ConsumerState<ExecutionCommitmentCardController> createState() =>
      _ExecutionCommitmentCardControllerState();
}

class _ExecutionCommitmentCardControllerState
    extends ConsumerState<ExecutionCommitmentCardController> {
  bool _busy = false;

  Future<void> _changeStatus(ExecutionCommitmentStatus status) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    if ((status == ExecutionCommitmentStatus.completed ||
            status == ExecutionCommitmentStatus.archived) &&
        !await _confirmOpenActions(
          context,
          widget.openActionCount ?? 0,
          archive: status == ExecutionCommitmentStatus.archived,
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(ref);
      await repo.updateCommitmentStatus(
        commitment: widget.commitment,
        status: status,
        sync: sync,
        progress: ExecutionProgressEntry(
          id: kExecutionUuid.v4(),
          projectId: widget.commitment.projectId,
          commitmentId: widget.commitment.id,
          kind: _commitmentProgressKind(status),
          note: _commitmentProgressNote(l10n, status),
          createdAt: sync.updatedAt,
          sync: sync,
        ),
      );
    } catch (_) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.executionCommitmentStatusUpdateFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExecutionCommitmentCard(
      commitment: widget.commitment,
      openActionCount: widget.openActionCount,
      blockedActionCount: widget.blockedActionCount,
      projectLabel: widget.projectLabel,
      busy: _busy,
      onOpen: _busy ? null : widget.onOpen,
      showActions: widget.showActions,
      showTypeLabel: widget.showTypeLabel,
      onCreateAction: widget.onCreateAction,
      onEdit: widget.onEdit,
      onRecordProgress: widget.onRecordProgress,
      onPause: () => _changeStatus(ExecutionCommitmentStatus.paused),
      onResume: () => _changeStatus(ExecutionCommitmentStatus.active),
      onComplete: () => _changeStatus(ExecutionCommitmentStatus.completed),
      onArchive: () => _changeStatus(ExecutionCommitmentStatus.archived),
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

ExecutionProgressKind _projectProgressKind(ExecutionProjectStatus status) {
  return switch (status) {
    ExecutionProjectStatus.completed => ExecutionProgressKind.completion,
    ExecutionProjectStatus.paused ||
    ExecutionProjectStatus.archived => ExecutionProgressKind.scopeChange,
    ExecutionProjectStatus.active => ExecutionProgressKind.checkin,
  };
}

String _projectProgressNote(
  AppLocalizations l10n,
  ExecutionProjectStatus status,
) {
  return switch (status) {
    ExecutionProjectStatus.paused => l10n.executionProjectPausedDefault,
    ExecutionProjectStatus.active => l10n.executionProjectResumedDefault,
    ExecutionProjectStatus.completed => l10n.executionProjectCompletedDefault,
    ExecutionProjectStatus.archived => l10n.executionProjectArchivedDefault,
  };
}

ExecutionProgressKind _commitmentProgressKind(
  ExecutionCommitmentStatus status,
) {
  return switch (status) {
    ExecutionCommitmentStatus.completed => ExecutionProgressKind.completion,
    ExecutionCommitmentStatus.paused ||
    ExecutionCommitmentStatus.archived => ExecutionProgressKind.scopeChange,
    ExecutionCommitmentStatus.active => ExecutionProgressKind.checkin,
  };
}

String _commitmentProgressNote(
  AppLocalizations l10n,
  ExecutionCommitmentStatus status,
) {
  return switch (status) {
    ExecutionCommitmentStatus.paused => l10n.executionCommitmentPausedDefault,
    ExecutionCommitmentStatus.active => l10n.executionCommitmentResumedDefault,
    ExecutionCommitmentStatus.completed =>
      l10n.executionCommitmentCompletedDefault,
    ExecutionCommitmentStatus.archived =>
      l10n.executionCommitmentArchivedDefault,
  };
}
