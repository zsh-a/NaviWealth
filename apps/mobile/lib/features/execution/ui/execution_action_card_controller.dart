import 'dart:async';

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/form_dirty_guard.dart';
import '../../../core/forms/form_submission.dart';
import '../../../core/lifeos/action_outcome.dart';
import '../../../core/logging/providers.dart';
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
    this.planLabel,
    this.onOpen,
    this.onSourceOpen,
    this.showActions = true,
    this.compact = false,
    this.outcome,
    this.focusSelected = false,
    this.onToggleFocus,
    this.completionBuilder,
  });

  /// Reuses status feedback and undo for the compact daily-focus row.
  final Widget Function(bool busy, VoidCallback onDone)? completionBuilder;

  final ExecutionAction action;
  final VoidCallback onEdit;
  final VoidCallback onRecordProgress;
  final String doneProgressNote;
  final String droppedProgressNote;
  final String? planLabel;
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
      final offers = ref.read(formUndoOfferProvider.notifier);
      final offer = FormUndoOffer(
        message: l10n.executionActionStatusUpdated(
          executionStatusLabel(l10n, status),
        ),
        action: FormUndoAction(undo.restore),
        actionLabel: l10n.commonUndo,
        successMessage: l10n.commonUndoSucceeded,
        failureMessage: (_) => l10n.commonUndoFailed,
        retryLabel: l10n.commonRetry,
        tag: 'execution-status',
      );
      offers.offer(offer);
      final logger = ref.read(loggerProvider);
      AppMessenger.show(
        feedbackContext,
        ToastKind.success,
        l10n.executionActionStatusUpdated(executionStatusLabel(l10n, status)),
        duration: const Duration(seconds: 6),
        actionLabel: l10n.commonUndo,
        onAction: () => unawaited(offers.run(feedbackContext, offer, logger)),
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

  Future<void> _blockWithReason() async {
    final l10n = AppLocalizations.of(context);
    final reason = await showGuardedFormSheet<String>(
      context: context,
      builder: (sheetContext, dirty) => AppSheet(
        title: l10n.executionBlockReasonTitle,
        child: _BlockReasonSheet(
          dirty: dirty,
          onSubmit: (value) {
            dirty.markPristine();
            Navigator.of(sheetContext).pop(value);
          },
        ),
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
    void complete() => unawaited(
      _changeStatus(
        ExecutionActionStatus.done,
        progressNote: widget.doneProgressNote,
      ),
    );
    final completionBuilder = widget.completionBuilder;
    if (completionBuilder != null) return completionBuilder(_busy, complete);
    return ExecutionActionCard(
      action: widget.action,
      busy: _busy,
      planLabel: widget.planLabel,
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
  const _BlockReasonSheet({required this.onSubmit, required this.dirty});

  final ValueChanged<String> onSubmit;
  final FormDirtyController dirty;

  @override
  State<_BlockReasonSheet> createState() => _BlockReasonSheetState();
}

class _BlockReasonSheetState extends State<_BlockReasonSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    widget.dirty.bindTextControllers([_controller]);
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
          label: Text(l10n.executionBlockReasonTitle),
          hint: l10n.executionBlockReasonHint,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          onSubmit: (_) {
            if (reason.isNotEmpty) widget.onSubmit(reason);
          },
        ),
        const SizedBox(height: AppSpacing.s12),
        AppActionButton(
          onPress: reason.isEmpty ? null : () => widget.onSubmit(reason),
          child: Text(l10n.executionActionBlock),
        ),
      ],
    );
  }
}
