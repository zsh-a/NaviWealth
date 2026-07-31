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
import 'execution_sheet_footer.dart';
import 'execution_widgets.dart';

Future<bool?> showExecutionProjectSheet({
  required BuildContext context,
  ExecutionProject? project,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => _ExecutionProjectForm(project: project, dirty: dirty),
  ).whenComplete(dirty.dispose);
}

class _ExecutionProjectForm extends ConsumerStatefulWidget {
  const _ExecutionProjectForm({required this.project, required this.dirty});

  final ExecutionProject? project;
  final FormDirtyController dirty;

  @override
  ConsumerState<_ExecutionProjectForm> createState() =>
      _ExecutionProjectFormState();
}

class _ExecutionProjectFormState extends ConsumerState<_ExecutionProjectForm>
    with FormSubmission<_ExecutionProjectForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late ExecutionHorizon _horizon;
  DateTime? _targetDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    _title.text = project?.title ?? '';
    _description.text = project?.description ?? '';
    _horizon = project?.horizon ?? ExecutionHorizon.open;
    _targetDate = project?.targetDate;
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
      tag: 'execution-project',
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.commonSaved,
      commit: () async {
        final repo = await ref.read(executionRepositoryProvider.future);
        final sync = await stampExecutionSync(ref);
        await repo.upsertProject(_buildProject(sync, title));
      },
    );
  }

  Future<void> _delete() async {
    final project = widget.project;
    if (_saving || project == null) return;
    final confirmed = await confirmExecutionDelete(
      context: context,
      item: project.title,
    );
    if (!confirmed || !mounted) return;
    final l10n = AppLocalizations.of(context);
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      leave: () => Navigator.of(context).pop(true),
      tag: 'execution-project-delete',
      failureMessage: (_) => l10n.commonDeleteFailed,
      successMessage: l10n.commonDeleted,
      commit: () async {
        final repo = await ref.read(executionRepositoryProvider.future);
        final sync = await stampExecutionSync(ref);
        await repo.softDeleteProject(project: project, sync: sync);
      },
    );
  }

  void _setSaving(bool value) {
    if (mounted && _saving != value) setState(() => _saving = value);
  }

  ExecutionProject _buildProject(SyncMeta sync, String title) {
    final existing = widget.project;
    return ExecutionProject(
      id: existing?.id ?? kExecutionUuid.v4(),
      title: title,
      description: _description.text.trim(),
      status: existing?.status ?? ExecutionProjectStatus.active,
      horizon: _horizon,
      targetDate: _targetDate,
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
    final isEditing = widget.project != null;
    return AppSheet(
      title: isEditing
          ? l10n.executionEditProjectTitle
          : l10n.executionCreateProjectTitle,
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
              label: Text(l10n.executionProjectField),
              hint: l10n.executionProjectTitleHint,
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
            FTextFormField(
              control: FTextFieldControl.managed(controller: _description),
              label: Text(l10n.executionDescriptionField),
              hint: l10n.executionProjectDescriptionHint,
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
