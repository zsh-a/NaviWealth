import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lifeos/action_outcome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/execution_models.dart';
import 'execution_action_sheet.dart';
import 'execution_widgets.dart';

class ExecutionActionCardController extends ConsumerStatefulWidget {
  const ExecutionActionCardController({
    super.key,
    required this.action,
    required this.onEdit,
    required this.onRecordProgress,
    required this.blockedProgressNote,
    required this.doneProgressNote,
    required this.droppedProgressNote,
    this.projectLabel,
    this.commitmentLabel,
    this.onOpen,
    this.showActions = true,
    this.outcome,
  });

  final ExecutionAction action;
  final VoidCallback onEdit;
  final VoidCallback onRecordProgress;
  final String blockedProgressNote;
  final String doneProgressNote;
  final String droppedProgressNote;
  final String? projectLabel;
  final String? commitmentLabel;
  final VoidCallback? onOpen;
  final bool showActions;
  final ActionOutcomeSummary? outcome;

  @override
  ConsumerState<ExecutionActionCardController> createState() =>
      _ExecutionActionCardControllerState();
}

class _ExecutionActionCardControllerState
    extends ConsumerState<ExecutionActionCardController> {
  bool _busy = false;

  Future<void> _changeStatus(
    ExecutionActionStatus status, {
    String? progressNote,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await updateExecutionActionStatus(
        ref: ref,
        action: widget.action,
        status: status,
        progressNote: progressNote,
      );
    } catch (_) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.executionActionStatusUpdateFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExecutionActionCard(
      action: widget.action,
      busy: _busy,
      projectLabel: widget.projectLabel,
      commitmentLabel: widget.commitmentLabel,
      onOpen: widget.onOpen,
      showActions: widget.showActions,
      outcome: widget.outcome,
      onEdit: _busy ? () {} : widget.onEdit,
      onRecordProgress: _busy ? () {} : widget.onRecordProgress,
      onStart: () => _changeStatus(ExecutionActionStatus.doing),
      onBlock: () => _changeStatus(
        ExecutionActionStatus.blocked,
        progressNote: widget.blockedProgressNote,
      ),
      onResume: () => _changeStatus(ExecutionActionStatus.doing),
      onDone: () => _changeStatus(
        ExecutionActionStatus.done,
        progressNote: widget.doneProgressNote,
      ),
      onDrop: () => _changeStatus(
        ExecutionActionStatus.dropped,
        progressNote: widget.droppedProgressNote,
      ),
    );
  }
}
