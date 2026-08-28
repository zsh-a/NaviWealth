import 'dart:async';

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

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
    required this.doneProgressNote,
    required this.droppedProgressNote,
    this.projectLabel,
    this.commitmentLabel,
    this.onOpen,
    this.onSourceOpen,
    this.showActions = true,
    this.compact = false,
    this.outcome,
    this.focusSelected = false,
    this.onToggleFocus,
  });

  final ExecutionAction action;
  final VoidCallback onEdit;
  final VoidCallback onRecordProgress;
  final String doneProgressNote;
  final String droppedProgressNote;
  final String? projectLabel;
  final String? commitmentLabel;
  final VoidCallback? onOpen;
  final VoidCallback? onSourceOpen;
  final bool showActions;
  final bool compact;
  final ActionOutcomeSummary? outcome;
  final bool focusSelected;
  final VoidCallback? onToggleFocus;

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
    final l10n = AppLocalizations.of(context);
    final feedbackContext = Navigator.of(context).context;
    AppMessenger.cacheOverlay(feedbackContext);
    setState(() => _busy = true);
    try {
      final undo = await updateExecutionActionStatus(
        ref: ref,
        action: widget.action,
        status: status,
        progressNote: progressNote,
      );
      if (!feedbackContext.mounted) return;
      AppMessenger.show(
        feedbackContext,
        ToastKind.success,
        l10n.executionActionStatusUpdated(executionStatusLabel(l10n, status)),
        duration: const Duration(seconds: 6),
        actionLabel: l10n.commonUndo,
        onAction: () => unawaited(_undoStatus(feedbackContext, undo, l10n)),
      );
    } catch (_) {
      if (feedbackContext.mounted) {
        AppMessenger.show(
          feedbackContext,
          ToastKind.error,
          l10n.executionActionStatusUpdateFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoStatus(
    BuildContext feedbackContext,
    ExecutionActionStatusUndo undo,
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

  Future<void> _blockWithReason() async {
    final l10n = AppLocalizations.of(context);
    final reason = await showAppSheet<String>(
      context: context,
      title: l10n.executionBlockReasonTitle,
      scrollable: false,
      builder: (sheetContext) => _BlockReasonSheet(
        onSubmit: (value) => Navigator.of(sheetContext).pop(value),
      ),
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    await _changeStatus(
      ExecutionActionStatus.blocked,
      progressNote: reason.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExecutionActionCard(
      action: widget.action,
      busy: _busy,
      projectLabel: widget.projectLabel,
      commitmentLabel: widget.commitmentLabel,
      onOpen: _busy ? null : widget.onOpen,
      onSourceOpen: _busy ? null : widget.onSourceOpen,
      showActions: widget.showActions,
      compact: widget.compact,
      outcome: widget.outcome,
      focusSelected: widget.focusSelected,
      onToggleFocus: widget.onToggleFocus,
      onEdit: widget.onEdit,
      onRecordProgress: widget.onRecordProgress,
      onStart: () => _changeStatus(
        ExecutionActionStatus.doing,
        progressNote: AppLocalizations.of(context)
            .executionProgressStartedDefault,
      ),
      onBlock: _blockWithReason,
      onResume: () => _changeStatus(
        ExecutionActionStatus.doing,
        progressNote: AppLocalizations.of(context)
            .executionProgressResumedDefault,
      ),
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

class _BlockReasonSheet extends StatefulWidget {
  const _BlockReasonSheet({required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<_BlockReasonSheet> createState() => _BlockReasonSheetState();
}

class _BlockReasonSheetState extends State<_BlockReasonSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = _controller.text.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTextField(
          control: FTextFieldControl.managed(controller: _controller),
          hint: l10n.executionBlockReasonHint,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          onSubmit: (_) {
            if (reason.isNotEmpty) widget.onSubmit(reason);
          },
        ),
        const SizedBox(height: AppSpacing.s12),
        FButton(
          onPress: reason.isEmpty ? null : () => widget.onSubmit(reason),
          child: Text(l10n.executionActionBlock),
        ),
      ],
    );
  }
}
