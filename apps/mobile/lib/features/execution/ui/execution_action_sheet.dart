import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_relation_picker.dart';
import 'execution_sheet_footer.dart';
import 'execution_widgets.dart';

Future<bool?> showExecutionActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  ExecutionAction? action,
  String? initialProjectId,
  String? initialCommitmentId,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => _ExecutionActionForm(
      ref: ref,
      action: action,
      initialProjectId: initialProjectId,
      initialCommitmentId: initialCommitmentId,
      dirty: dirty,
    ),
  ).whenComplete(dirty.dispose);
}

class _ExecutionActionForm extends StatefulWidget {
  const _ExecutionActionForm({
    required this.ref,
    required this.action,
    required this.initialProjectId,
    required this.initialCommitmentId,
    required this.dirty,
  });

  final WidgetRef ref;
  final ExecutionAction? action;
  final String? initialProjectId;
  final String? initialCommitmentId;
  final FormDirtyController dirty;

  @override
  State<_ExecutionActionForm> createState() => _ExecutionActionFormState();
}

class _ExecutionActionFormState extends State<_ExecutionActionForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  late ExecutionActionStatus _status;
  late ExecutionPriority _priority;
  DateTime? _dueAt;
  DateTime? _scheduledFor;
  String? _projectId;
  String? _commitmentId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final action = widget.action;
    _title.text = action?.title ?? '';
    _note.text = action?.note ?? '';
    _status = action?.status ?? ExecutionActionStatus.todo;
    _priority = action?.priority ?? ExecutionPriority.normal;
    _dueAt = action?.dueAt;
    _scheduledFor = action?.scheduledFor;
    _projectId = action == null ? widget.initialProjectId : action.projectId;
    _commitmentId = action == null
        ? widget.initialCommitmentId
        : action.commitmentId;
    widget.dirty.bindTextControllers([_title, _note]);
    _title.addListener(_onTitleChanged);
  }

  void _onTitleChanged() {
    if (mounted && !_saving) setState(() {});
  }

  @override
  void dispose() {
    _title.removeListener(_onTitleChanged);
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _canSave => !_saving && _title.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final title = _title.text.trim();
    setState(() => _saving = true);
    try {
      final repo = await widget.ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(widget.ref);
      await repo.upsertAction(_buildAction(sync, title));
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ExecutionAction _buildAction(SyncMeta sync, String title) {
    final existing = widget.action;
    return ExecutionAction(
      id: existing?.id ?? kExecutionUuid.v4(),
      title: title,
      note: _note.text.trim(),
      status: _status,
      priority: _priority,
      dueAt: _dueAt,
      scheduledFor: _scheduledFor,
      projectId: _projectId,
      commitmentId: _commitmentId,
      source: existing?.source ?? const ExecutionSourceRef(),
      createdAt: existing?.createdAt ?? sync.updatedAt,
      completedAt: _completedAt(sync),
      sync: sync,
    );
  }

  DateTime? _completedAt(SyncMeta sync) {
    final existing = widget.action;
    final closed =
        _status == ExecutionActionStatus.done ||
        _status == ExecutionActionStatus.dropped;
    if (!closed) return null;
    if (existing?.status == _status && existing?.completedAt != null) {
      return existing!.completedAt;
    }
    return sync.updatedAt;
  }

  void _markDirty() => widget.dirty.markDirty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projects =
        widget.ref.watch(executionProjectsProvider).value ??
        const <ExecutionProject>[];
    final commitments =
        widget.ref.watch(executionCommitmentsProvider).value ??
        const <ExecutionCommitment>[];
    final isEditing = widget.action != null;

    return AppSheet(
      title: isEditing
          ? l10n.executionEditActionTitle
          : l10n.executionCreateActionTitle,
      footer: ExecutionSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        enabled: _canSave,
        busy: _saving,
        onSubmit: _save,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FTextFormField(
              control: FTextFieldControl.managed(controller: _title),
              label: Text(l10n.executionActionField),
              hint: l10n.executionActionTitleHint,
              maxLines: 1,
              textInputAction: TextInputAction.next,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? l10n.executionTitleRequired
                  : null,
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(l10n.executionStatusField, style: context.captionLabelStyle),
            const SizedBox(height: AppSpacing.s6),
            SegmentedRow<ExecutionActionStatus>(
              options: ExecutionActionStatus.values,
              value: _status,
              labelOf: (status) => executionStatusLabel(l10n, status),
              iconOf: _statusIcon,
              onChanged: _saving
                  ? (_) {}
                  : (status) {
                      setState(() => _status = status);
                      _markDirty();
                    },
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(l10n.executionPriorityField, style: context.captionLabelStyle),
            const SizedBox(height: AppSpacing.s6),
            SegmentedRow<ExecutionPriority>(
              options: ExecutionPriority.values,
              value: _priority,
              labelOf: (priority) => executionPriorityLabel(l10n, priority),
              iconOf: _priorityIcon,
              onChanged: _saving
                  ? (_) {}
                  : (priority) {
                      setState(() => _priority = priority);
                      _markDirty();
                    },
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DateField(
                    label: l10n.executionScheduledForField,
                    initialValue: _scheduledFor,
                    enabled: !_saving,
                    onChanged: (value) {
                      setState(() => _scheduledFor = value);
                      _markDirty();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: DateField(
                    label: l10n.executionDueAtField,
                    initialValue: _dueAt,
                    enabled: !_saving,
                    onChanged: (value) {
                      setState(() => _dueAt = value);
                      _markDirty();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            FormPickerRow(
              label: l10n.executionProjectField,
              value: executionProjectPickerLabel(l10n, projects, _projectId),
              leading: const Icon(FLucideIcons.folder),
              enabled: !_saving,
              onPress: () async {
                final picked = await showExecutionProjectPicker(
                  context: context,
                  projects: projects,
                  selectedId: _projectId,
                );
                if (picked == null) return;
                setState(() {
                  _projectId = picked == kExecutionPickerNone ? null : picked;
                });
                _markDirty();
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            FormPickerRow(
              label: l10n.executionCommitmentField,
              value: executionCommitmentPickerLabel(
                l10n,
                commitments,
                _commitmentId,
              ),
              leading: const Icon(FLucideIcons.target),
              enabled: !_saving,
              onPress: () async {
                final picked = await showExecutionCommitmentPicker(
                  context: context,
                  commitments: commitments,
                  selectedId: _commitmentId,
                );
                if (picked == null) return;
                setState(() {
                  _commitmentId = picked == kExecutionPickerNone
                      ? null
                      : picked;
                });
                _markDirty();
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _note),
              label: Text(l10n.commonNote),
              hint: l10n.executionActionNoteHint,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
            ),
          ],
        ),
      ),
    );
  }
}

IconData _statusIcon(ExecutionActionStatus status) {
  return switch (status) {
    ExecutionActionStatus.todo => FLucideIcons.circle,
    ExecutionActionStatus.doing => FLucideIcons.play,
    ExecutionActionStatus.blocked => FLucideIcons.octagonAlert,
    ExecutionActionStatus.done => FLucideIcons.check,
    ExecutionActionStatus.dropped => FLucideIcons.archive,
  };
}

IconData _priorityIcon(ExecutionPriority priority) {
  return switch (priority) {
    ExecutionPriority.low => FLucideIcons.arrowDown,
    ExecutionPriority.normal => FLucideIcons.minus,
    ExecutionPriority.high => FLucideIcons.flag,
  };
}

Future<void> updateExecutionActionStatus({
  required WidgetRef ref,
  required ExecutionAction action,
  required ExecutionActionStatus status,
  String? progressNote,
}) async {
  final repo = await ref.read(executionRepositoryProvider.future);
  final sync = await stampExecutionSync(ref);
  await repo.updateActionStatus(
    action: action,
    status: status,
    sync: sync,
    progressId: progressNote == null ? null : kExecutionUuid.v4(),
    progressNote: progressNote,
  );
}
