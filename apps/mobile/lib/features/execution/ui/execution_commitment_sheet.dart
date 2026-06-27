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

Future<bool?> showExecutionCommitmentSheet({
  required BuildContext context,
  required WidgetRef ref,
  ExecutionCommitment? commitment,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => _ExecutionCommitmentForm(
      ref: ref,
      commitment: commitment,
      dirty: dirty,
    ),
  ).whenComplete(dirty.dispose);
}

class _ExecutionCommitmentForm extends StatefulWidget {
  const _ExecutionCommitmentForm({
    required this.ref,
    required this.commitment,
    required this.dirty,
  });

  final WidgetRef ref;
  final ExecutionCommitment? commitment;
  final FormDirtyController dirty;

  @override
  State<_ExecutionCommitmentForm> createState() =>
      _ExecutionCommitmentFormState();
}

class _ExecutionCommitmentFormState extends State<_ExecutionCommitmentForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late ExecutionCommitmentStatus _status;
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
    _status = commitment?.status ?? ExecutionCommitmentStatus.active;
    _horizon = commitment?.horizon ?? ExecutionHorizon.open;
    _targetDate = commitment?.targetDate;
    _projectId = commitment?.projectId;
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
      await repo.upsertCommitment(_buildCommitment(sync, title));
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ExecutionCommitment _buildCommitment(SyncMeta sync, String title) {
    final existing = widget.commitment;
    return ExecutionCommitment(
      id: existing?.id ?? kExecutionUuid.v4(),
      title: title,
      description: _description.text.trim(),
      status: _status,
      horizon: _horizon,
      targetDate: _targetDate,
      projectId: _projectId,
      source: existing?.source ?? const ExecutionSourceRef(),
      createdAt: existing?.createdAt ?? sync.updatedAt,
      completedAt: _completedAt(sync),
      sync: sync,
    );
  }

  DateTime? _completedAt(SyncMeta sync) {
    final existing = widget.commitment;
    final closed =
        _status == ExecutionCommitmentStatus.completed ||
        _status == ExecutionCommitmentStatus.archived;
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
            Text(l10n.executionStatusField, style: context.captionLabelStyle),
            const SizedBox(height: AppSpacing.s6),
            SegmentedRow<ExecutionCommitmentStatus>(
              options: ExecutionCommitmentStatus.values,
              value: _status,
              labelOf: (status) => executionCommitmentStatusLabel(l10n, status),
              iconOf: _commitmentStatusIcon,
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
            FTextFormField(
              control: FTextFieldControl.managed(controller: _description),
              label: Text(l10n.executionDescriptionField),
              hint: l10n.executionCommitmentDescriptionHint,
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

IconData _commitmentStatusIcon(ExecutionCommitmentStatus status) {
  return switch (status) {
    ExecutionCommitmentStatus.active => FLucideIcons.play,
    ExecutionCommitmentStatus.paused => FLucideIcons.pause,
    ExecutionCommitmentStatus.completed => FLucideIcons.check,
    ExecutionCommitmentStatus.archived => FLucideIcons.archive,
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
