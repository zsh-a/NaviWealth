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
import 'execution_delete_confirm.dart';
import 'execution_sheet_footer.dart';
import 'execution_widgets.dart';

Future<bool?> showExecutionProjectSheet({
  required BuildContext context,
  required WidgetRef ref,
  ExecutionProject? project,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) =>
        _ExecutionProjectForm(ref: ref, project: project, dirty: dirty),
  ).whenComplete(dirty.dispose);
}

class _ExecutionProjectForm extends StatefulWidget {
  const _ExecutionProjectForm({
    required this.ref,
    required this.project,
    required this.dirty,
  });

  final WidgetRef ref;
  final ExecutionProject? project;
  final FormDirtyController dirty;

  @override
  State<_ExecutionProjectForm> createState() => _ExecutionProjectFormState();
}

class _ExecutionProjectFormState extends State<_ExecutionProjectForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late ExecutionProjectStatus _status;
  late ExecutionHorizon _horizon;
  DateTime? _targetDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    _title.text = project?.title ?? '';
    _description.text = project?.description ?? '';
    _status = project?.status ?? ExecutionProjectStatus.active;
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
    final title = _title.text.trim();
    setState(() => _saving = true);
    try {
      final repo = await widget.ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(widget.ref);
      await repo.upsertProject(_buildProject(sync, title));
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final project = widget.project;
    if (_saving || project == null) return;
    final confirmed = await confirmExecutionDelete(
      context: context,
      item: project.title,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      final repo = await widget.ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(widget.ref);
      await repo.softDeleteProject(project: project, sync: sync);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ExecutionProject _buildProject(SyncMeta sync, String title) {
    final existing = widget.project;
    return ExecutionProject(
      id: existing?.id ?? kExecutionUuid.v4(),
      title: title,
      description: _description.text.trim(),
      status: _status,
      horizon: _horizon,
      targetDate: _targetDate,
      source: existing?.source ?? const ExecutionSourceRef(),
      createdAt: existing?.createdAt ?? sync.updatedAt,
      completedAt: _completedAt(sync),
      sync: sync,
    );
  }

  DateTime? _completedAt(SyncMeta sync) {
    final existing = widget.project;
    final closed =
        _status == ExecutionProjectStatus.completed ||
        _status == ExecutionProjectStatus.archived;
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
            Text(l10n.executionStatusField, style: context.captionLabelStyle),
            const SizedBox(height: AppSpacing.s6),
            SegmentedRow<ExecutionProjectStatus>(
              options: ExecutionProjectStatus.values,
              value: _status,
              labelOf: (status) => executionProjectStatusLabel(l10n, status),
              iconOf: _projectStatusIcon,
              onChanged: _saving
                  ? (_) {}
                  : (status) {
                      setState(() => _status = status);
                      _markDirty();
                    },
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(l10n.executionHorizonField, style: context.captionLabelStyle),
            const SizedBox(height: AppSpacing.s6),
            SegmentedRow<ExecutionHorizon>(
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

IconData _projectStatusIcon(ExecutionProjectStatus status) {
  return switch (status) {
    ExecutionProjectStatus.active => FLucideIcons.play,
    ExecutionProjectStatus.paused => FLucideIcons.pause,
    ExecutionProjectStatus.completed => FLucideIcons.check,
    ExecutionProjectStatus.archived => FLucideIcons.archive,
  };
}

IconData _horizonIcon(ExecutionHorizon horizon) {
  return switch (horizon) {
    ExecutionHorizon.week => FLucideIcons.calendarDays,
    ExecutionHorizon.month => FLucideIcons.calendar,
    ExecutionHorizon.quarter => FLucideIcons.calendarRange,
    ExecutionHorizon.open => FLucideIcons.infinity,
  };
}
