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

Future<bool?> showExecutionCommitmentSheet({
  required BuildContext context,
  ExecutionCommitment? commitment,
  String? initialProjectId,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => _ExecutionCommitmentForm(
      commitment: commitment,
      initialProjectId: initialProjectId,
      dirty: dirty,
    ),
  ).whenComplete(dirty.dispose);
}

class _ExecutionCommitmentForm extends ConsumerStatefulWidget {
  const _ExecutionCommitmentForm({
    required this.commitment,
    required this.initialProjectId,
    required this.dirty,
  });

  final ExecutionCommitment? commitment;
  final String? initialProjectId;
  final FormDirtyController dirty;

  @override
  ConsumerState<_ExecutionCommitmentForm> createState() =>
      _ExecutionCommitmentFormState();
}

class _ExecutionCommitmentFormState
    extends ConsumerState<_ExecutionCommitmentForm>
    with FormSubmission<_ExecutionCommitmentForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late ExecutionHorizon _horizon;
  DateTime? _targetDate;
  String? _projectId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final commitment = widget.commitment;
    _title.text = commitment?.title ?? '';
    _description.text = commitment?.description ?? '';
    _horizon = commitment?.horizon ?? ExecutionHorizon.open;
    _targetDate = commitment?.targetDate;
    _projectId = commitment?.projectId ?? widget.initialProjectId;
    widget.dirty.bindTextControllers([_title, _description]);
    _title.addListener(_onTitleChanged);
  }

  void _onTitleChanged() {
    if (mounted && !_saving) setState(() {});
  }

  @override
  void dispose() {
    _title.removeListener(_onTitleChanged);
    _title.dispose();
    _description.dispose();
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
      tag: 'execution-commitment',
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.commonSaved,
      commit: () async {
        final repo = await ref.read(executionRepositoryProvider.future);
        final sync = await stampExecutionSync(ref);
        await repo.upsertCommitment(_buildCommitment(sync, title));
      },
    );
  }

  Future<void> _delete() async {
    final commitment = widget.commitment;
    if (_saving || commitment == null) return;
    final confirmed = await confirmExecutionDelete(
      context: context,
      item: commitment.title,
    );
    if (!confirmed || !mounted) return;
    final l10n = AppLocalizations.of(context);
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      leave: () => Navigator.of(context).pop(true),
      tag: 'execution-commitment-delete',
      failureMessage: (_) => l10n.commonDeleteFailed,
      successMessage: l10n.commonDeleted,
      commit: () async {
        final repo = await ref.read(executionRepositoryProvider.future);
        final sync = await stampExecutionSync(ref);
        await repo.softDeleteCommitment(commitment: commitment, sync: sync);
      },
    );
  }

  void _setSaving(bool value) {
    if (mounted && _saving != value) setState(() => _saving = value);
  }

  ExecutionCommitment _buildCommitment(SyncMeta sync, String title) {
    final existing = widget.commitment;
    return ExecutionCommitment(
      id: existing?.id ?? kExecutionUuid.v4(),
      title: title,
      description: _description.text.trim(),
      status: existing?.status ?? ExecutionCommitmentStatus.active,
      horizon: _horizon,
      targetDate: _targetDate,
      projectId: _projectId,
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
    final selectedProject = _projectId == null || _projectId!.isEmpty
        ? null
        : ref.watch(executionProjectByIdProvider(_projectId!)).value;
    final isEditing = widget.commitment != null;

    return AppSheet(
      title: isEditing
          ? l10n.executionEditCommitmentTitle
          : l10n.executionCreateCommitmentTitle,
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
              label: Text(l10n.executionCommitmentField),
              hint: l10n.executionCommitmentTitleHint,
              maxLines: 1,
              textInputAction: TextInputAction.next,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? l10n.executionTitleRequired
                  : null,
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(l10n.executionHorizonField, style: context.captionLabelStyle),
            const SizedBox(height: AppSpacing.s6),
            AppAdaptiveChoice<ExecutionHorizon>(
              title: l10n.executionHorizonField,
              options: ExecutionHorizon.values,
              value: _horizon,
              labelOf: (horizon) => executionHorizonLabel(l10n, horizon),
              iconOf: _horizonIcon,
              onChanged: _saving
                  ? (_) {}
                  : (horizon) {
                      setState(() => _horizon = horizon);
                      _markDirty();
                    },
            ),
            const SizedBox(height: AppSpacing.s12),
            DateField(
              label: l10n.executionTargetDateField,
              initialValue: _targetDate,
              enabled: !_saving,
              onChanged: (value) {
                setState(() => _targetDate = value);
                _markDirty();
              },
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
                  _projectId = picked == kExecutionPickerNone ? null : picked;
                });
                _markDirty();
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _description),
              label: Text(l10n.executionDescriptionField),
              hint: l10n.executionCommitmentDescriptionHint,
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

IconData _horizonIcon(ExecutionHorizon horizon) {
  return switch (horizon) {
    ExecutionHorizon.week => FLucideIcons.calendarDays,
    ExecutionHorizon.month => FLucideIcons.calendar,
    ExecutionHorizon.quarter => FLucideIcons.calendarRange,
    ExecutionHorizon.open => FLucideIcons.infinity,
  };
}
