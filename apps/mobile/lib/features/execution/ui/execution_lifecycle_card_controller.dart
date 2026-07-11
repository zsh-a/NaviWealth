import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    this.showActions = true,
  });

  final ExecutionProject project;
  final VoidCallback onCreateAction;
  final VoidCallback onEdit;
  final VoidCallback onRecordProgress;
  final int? openActionCount;
  final int? blockedActionCount;
  final bool showActions;

  @override
  ConsumerState<ExecutionProjectCardController> createState() =>
      _ExecutionProjectCardControllerState();
}

class _ExecutionProjectCardControllerState
    extends ConsumerState<ExecutionProjectCardController> {
  bool _busy = false;

  Future<void> _changeStatus(ExecutionProjectStatus status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(ref);
      await repo.updateProjectStatus(
        project: widget.project,
        status: status,
        sync: sync,
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
      busy: _busy,
      showActions: widget.showActions,
      onCreateAction: _busy ? () {} : widget.onCreateAction,
      onEdit: _busy ? () {} : widget.onEdit,
      onRecordProgress: _busy ? () {} : widget.onRecordProgress,
      onPause: () => _changeStatus(ExecutionProjectStatus.paused),
      onResume: () => _changeStatus(ExecutionProjectStatus.active),
      onComplete: () => _changeStatus(ExecutionProjectStatus.completed),
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
    this.onOpen,
    this.showActions = true,
  });

  final ExecutionCommitment commitment;
  final VoidCallback onCreateAction;
  final VoidCallback onEdit;
  final VoidCallback onRecordProgress;
  final int? openActionCount;
  final int? blockedActionCount;
  final VoidCallback? onOpen;
  final bool showActions;

  @override
  ConsumerState<ExecutionCommitmentCardController> createState() =>
      _ExecutionCommitmentCardControllerState();
}

class _ExecutionCommitmentCardControllerState
    extends ConsumerState<ExecutionCommitmentCardController> {
  bool _busy = false;

  Future<void> _changeStatus(ExecutionCommitmentStatus status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(ref);
      await repo.updateCommitmentStatus(
        commitment: widget.commitment,
        status: status,
        sync: sync,
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
      busy: _busy,
      onOpen: widget.onOpen,
      showActions: widget.showActions,
      onCreateAction: _busy ? () {} : widget.onCreateAction,
      onEdit: _busy ? () {} : widget.onEdit,
      onRecordProgress: _busy ? () {} : widget.onRecordProgress,
      onPause: () => _changeStatus(ExecutionCommitmentStatus.paused),
      onResume: () => _changeStatus(ExecutionCommitmentStatus.active),
      onComplete: () => _changeStatus(ExecutionCommitmentStatus.completed),
    );
  }
}
