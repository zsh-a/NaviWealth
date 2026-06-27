import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_relation_picker.dart';
import 'execution_sheet_footer.dart';
import 'execution_widgets.dart';

Future<bool?> showExecutionProgressSheet({
  required BuildContext context,
  required WidgetRef ref,
  ExecutionAction? action,
  String? projectId,
  String? commitmentId,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => _ExecutionProgressForm(
      ref: ref,
      dirty: dirty,
      action: action,
      projectId: projectId,
      commitmentId: commitmentId,
    ),
  ).whenComplete(dirty.dispose);
}

class _ExecutionProgressForm extends StatefulWidget {
  const _ExecutionProgressForm({
    required this.ref,
    required this.dirty,
    required this.action,
    required this.projectId,
    required this.commitmentId,
  });

  final WidgetRef ref;
  final FormDirtyController dirty;
  final ExecutionAction? action;
  final String? projectId;
  final String? commitmentId;

  @override
  State<_ExecutionProgressForm> createState() => _ExecutionProgressFormState();
}

class _ExecutionProgressFormState extends State<_ExecutionProgressForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _note = TextEditingController();
  late ExecutionProgressKind _kind;
  String? _actionId;
  String? _projectId;
  String? _commitmentId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _kind = ExecutionProgressKind.checkin;
    _actionId = widget.action?.id;
    _projectId = widget.action?.projectId ?? widget.projectId;
    _commitmentId = widget.action?.commitmentId ?? widget.commitmentId;
    widget.dirty.bindTextControllers([_note]);
    _note.addListener(_onNoteChanged);
  }

  @override
  void dispose() {
    _note.removeListener(_onNoteChanged);
    _note.dispose();
    super.dispose();
  }

  void _onNoteChanged() {
    if (mounted && !_saving) setState(() {});
  }

  bool get _canSave => !_saving && _note.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final repo = await widget.ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(widget.ref);
      await repo.upsertProgress(
        ExecutionProgressEntry(
          id: kExecutionUuid.v4(),
          actionId: _actionId,
          projectId: _projectId,
          commitmentId: _commitmentId,
          kind: _kind,
          note: _note.text.trim(),
          createdAt: sync.updatedAt,
          sync: sync,
        ),
      );
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _markDirty() => widget.dirty.markDirty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions =
        widget.ref.watch(executionOpenActionsProvider).value ??
        const <ExecutionAction>[];
    final projects =
        widget.ref.watch(executionProjectsProvider).value ??
        const <ExecutionProject>[];
    final commitments =
        widget.ref.watch(executionCommitmentsProvider).value ??
        const <ExecutionCommitment>[];
    return AppSheet(
      title: l10n.executionCreateProgressTitle,
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
            Text(
              l10n.executionProgressKindField,
              style: context.captionLabelStyle,
            ),
            const SizedBox(height: AppSpacing.s6),
            SegmentedRow<ExecutionProgressKind>(
              options: ExecutionProgressKind.values,
              value: _kind,
              labelOf: (kind) => executionProgressKindLabel(l10n, kind),
              iconOf: _progressKindIcon,
              onChanged: _saving
                  ? (_) {}
                  : (kind) {
                      setState(() => _kind = kind);
                      _markDirty();
                    },
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _note),
              label: Text(l10n.executionProgressNoteField),
              hint: l10n.executionProgressNoteHint,
              minLines: 3,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? l10n.executionProgressNoteRequired
                  : null,
            ),
            const SizedBox(height: AppSpacing.s12),
            FormPickerRow(
              label: l10n.executionActionField,
              value: executionActionPickerLabel(l10n, actions, _actionId),
              leading: const Icon(FLucideIcons.listTodo),
              enabled: !_saving,
              onPress: () async {
                final picked = await showExecutionActionPicker(
                  context: context,
                  actions: actions,
                  selectedId: _actionId,
                );
                if (picked == null) return;
                setState(() {
                  if (picked == kExecutionPickerNone) {
                    _actionId = null;
                    return;
                  }
                  _actionId = picked;
                  final action = actions
                      .where((ExecutionAction a) => a.id == picked)
                      .first;
                  _projectId = action.projectId;
                  _commitmentId = action.commitmentId;
                });
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
          ],
        ),
      ),
    );
  }
}

IconData _progressKindIcon(ExecutionProgressKind kind) {
  return switch (kind) {
    ExecutionProgressKind.checkin => FLucideIcons.messageSquareText,
    ExecutionProgressKind.blocker => FLucideIcons.octagonAlert,
    ExecutionProgressKind.scopeChange => FLucideIcons.gitBranch,
    ExecutionProgressKind.completion => FLucideIcons.check,
    ExecutionProgressKind.dropped => FLucideIcons.archive,
  };
}
