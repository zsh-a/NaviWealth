import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/forms.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_delete_confirm.dart';
import 'execution_relation_picker.dart';
import 'execution_sheet_footer.dart';
import 'execution_widgets.dart';

Future<bool?> showExecutionActionSheet({
  required BuildContext context,
  ExecutionAction? action,
  String? initialProjectId,
  String? initialCommitmentId,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => _ExecutionActionForm(
      action: action,
      initialProjectId: initialProjectId,
      initialCommitmentId: initialCommitmentId,
      dirty: dirty,
    ),
  ).whenComplete(dirty.dispose);
}

class _ExecutionActionForm extends ConsumerStatefulWidget {
  const _ExecutionActionForm({
    required this.action,
    required this.initialProjectId,
    required this.initialCommitmentId,
    required this.dirty,
  });

  final ExecutionAction? action;
  final String? initialProjectId;
  final String? initialCommitmentId;
  final FormDirtyController dirty;

  @override
  ConsumerState<_ExecutionActionForm> createState() =>
      _ExecutionActionFormState();
}

class _ExecutionActionFormState extends ConsumerState<_ExecutionActionForm>
    with FormSubmission<_ExecutionActionForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
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
    final l10n = AppLocalizations.of(context);
    final title = _title.text.trim();
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      leave: () => Navigator.of(context).pop(true),
      tag: 'execution-action',
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.commonSaved,
      commit: () async {
        final repo = await ref.read(executionRepositoryProvider.future);
        final sync = await stampExecutionSync(ref);
        await repo.upsertAction(_buildAction(sync, title));
      },
    );
  }

  Future<void> _delete() async {
    final action = widget.action;
    if (_saving || action == null) return;
    final confirmed = await confirmExecutionDelete(
      context: context,
      item: action.title,
    );
    if (!confirmed || !mounted) return;
    final l10n = AppLocalizations.of(context);
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      leave: () => Navigator.of(context).pop(true),
      tag: 'execution-action-delete',
      failureMessage: (_) => l10n.commonDeleteFailed,
      successMessage: l10n.commonDeleted,
      commit: () async {
        final repo = await ref.read(executionRepositoryProvider.future);
        final sync = await stampExecutionSync(ref);
        await repo.softDeleteAction(action: action, sync: sync);
      },
    );
  }

  void _setSaving(bool value) {
    if (mounted && _saving != value) setState(() => _saving = value);
  }

  ExecutionAction _buildAction(SyncMeta sync, String title) {
    final existing = widget.action;
    return ExecutionAction(
      id: existing?.id ?? kExecutionUuid.v4(),
      title: title,
      note: _note.text.trim(),
      status: existing?.status ?? ExecutionActionStatus.todo,
      priority: _priority,
      dueAt: _dueAt,
      scheduledFor: _scheduledFor,
      projectId: _projectId,
      commitmentId: _commitmentId,
      source: existing?.source ?? const ExecutionSourceRef(),
      createdAt: existing?.createdAt ?? sync.updatedAt,
      completedAt: existing?.completedAt,
      sync: sync,
    );
  }

  void _markDirty() => widget.dirty.markDirty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projects =
        ref.watch(executionProjectsProvider).value ??
        const <ExecutionProject>[];
    final commitments =
        ref.watch(executionCommitmentsProvider).value ??
        const <ExecutionCommitment>[];
    final selectedProject = _projectId == null || _projectId!.isEmpty
        ? null
        : ref.watch(executionProjectByIdProvider(_projectId!)).value;
    final selectedCommitment = _commitmentId == null || _commitmentId!.isEmpty
        ? null
        : ref.watch(executionCommitmentByIdProvider(_commitmentId!)).value;
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
            if (submissionFailureMessage != null) ...[
              AppStatusBanner(
                kind: AppStatusKind.error,
                message: submissionFailureMessage!,
                compact: true,
              ),
              const SizedBox(height: AppSpacing.s12),
            ],
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
              value:
                  selectedProject?.title ??
                  executionProjectPickerLabel(l10n, projects, _projectId),
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
                  final next = executionRelationAfterProjectPick(
                    commitments: commitments,
                    currentCommitmentId: _commitmentId,
                    pickedProjectId: picked,
                  );
                  _projectId = next.projectId;
                  _commitmentId = next.commitmentId;
                });
                _markDirty();
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            FormPickerRow(
              label: l10n.executionCommitmentField,
              value:
                  selectedCommitment?.title ??
                  executionCommitmentPickerLabel(
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
                  final next = executionRelationAfterCommitmentPick(
                    commitments: commitments,
                    currentProjectId: _projectId,
                    pickedCommitmentId: picked,
                  );
                  _projectId = next.projectId;
                  _commitmentId = next.commitmentId;
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
            if (isEditing) ...[
              const SizedBox(height: AppSpacing.s16),
              const AppDivider(),
              const SizedBox(height: AppSpacing.s12),
              FButton(
                variant: FButtonVariant.destructive,
                onPress: _saving ? null : _delete,
                child: Text(l10n.commonDelete),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
