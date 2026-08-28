import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/forms.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_sheet_footer.dart';
import 'execution_widgets.dart';

Future<bool?> showExecutionProgressSheet({
  required BuildContext context,
  ExecutionProgressEntry? progress,
  ExecutionAction? action,
  String? projectId,
  String? commitmentId,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => _ExecutionProgressForm(
      dirty: dirty,
      progress: progress,
      action: action,
      projectId: projectId,
      commitmentId: commitmentId,
    ),
  ).whenComplete(dirty.dispose);
}

class _ExecutionProgressForm extends ConsumerStatefulWidget {
  const _ExecutionProgressForm({
    required this.dirty,
    required this.progress,
    required this.action,
    required this.projectId,
    required this.commitmentId,
  });

  final FormDirtyController dirty;
  final ExecutionProgressEntry? progress;
  final ExecutionAction? action;
  final String? projectId;
  final String? commitmentId;

  @override
  ConsumerState<_ExecutionProgressForm> createState() =>
      _ExecutionProgressFormState();
}

class _ExecutionProgressFormState extends ConsumerState<_ExecutionProgressForm>
    with FormSubmission<_ExecutionProgressForm> {
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
    final progress = widget.progress;
    _note.text = progress?.note ?? '';
    _kind = progress?.kind ?? ExecutionProgressKind.checkin;
    _actionId = progress?.actionId ?? widget.action?.id;
    _projectId =
        progress?.projectId ?? widget.action?.projectId ?? widget.projectId;
    _commitmentId =
        progress?.commitmentId ??
        widget.action?.commitmentId ??
        widget.commitmentId;
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
    final l10n = AppLocalizations.of(context);
    final note = _note.text.trim();
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      leave: () => Navigator.of(context).pop(true),
      tag: 'execution-progress',
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.commonSaved,
      commit: () async {
        final repo = await ref.read(executionRepositoryProvider.future);
        final sync = await stampExecutionSync(ref);
        await repo.recordProgress(
          ExecutionProgressEntry(
            id: widget.progress?.id ?? kExecutionUuid.v4(),
            actionId: _actionId,
            projectId: _projectId,
            commitmentId: _commitmentId,
            kind: _kind,
            note: note,
            createdAt: widget.progress?.createdAt ?? sync.updatedAt,
            sync: sync,
          ),
        );
      },
    );
  }

  void _setSaving(bool value) {
    if (mounted && _saving != value) setState(() => _saving = value);
  }

  void _markDirty() => widget.dirty.markDirty();

  List<ExecutionProgressKind> get _availableKinds {
    final kinds = <ExecutionProgressKind>[
      ExecutionProgressKind.checkin,
      ExecutionProgressKind.scopeChange,
    ];
    // Blocking an Action is a lifecycle operation with a required reason.
    // Keep that flow on the Action itself instead of asking users to decide
    // whether a progress note should also mutate status.
    if (widget.action == null) {
      kinds.insert(1, ExecutionProgressKind.blocker);
    }
    final existing = widget.progress?.kind;
    if (existing != null && !kinds.contains(existing)) kinds.add(existing);
    return kinds;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedAction = _actionId == null || _actionId!.isEmpty
        ? null
        : ref.watch(executionActionByIdProvider(_actionId!)).value;
    final selectedProject = _projectId == null || _projectId!.isEmpty
        ? null
        : ref.watch(executionProjectByIdProvider(_projectId!)).value;
    final selectedCommitment = _commitmentId == null || _commitmentId!.isEmpty
        ? null
        : ref.watch(executionCommitmentByIdProvider(_commitmentId!)).value;
    final contextValue =
        selectedAction?.title ??
        widget.action?.title ??
        selectedCommitment?.title ??
        selectedProject?.title ??
        (_actionId?.isNotEmpty == true
            ? l10n.executionUnknownAction
            : _commitmentId?.isNotEmpty == true
            ? l10n.executionUnknownCommitment
            : _projectId?.isNotEmpty == true
            ? l10n.executionUnknownProject
            : l10n.executionNoRelation);
    return AppSheet(
      title: widget.progress == null
          ? l10n.executionCreateProgressTitle
          : l10n.executionEditProgressTitle,
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
            Text(
              l10n.executionProgressKindField,
              style: context.captionLabelStyle,
            ),
            const SizedBox(height: AppSpacing.s6),
            AppAdaptiveChoice<ExecutionProgressKind>(
              title: l10n.executionProgressKindField,
              options: _availableKinds,
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
            _ProgressContextSummary(
              label: l10n.executionRelationField,
              value: contextValue,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressContextSummary extends StatelessWidget {
  const _ProgressContextSummary({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard.flat(
      padding: AppPageRhythm.densePadding,
      child: Row(
        children: [
          AppIconTile(
            icon: FLucideIcons.layers,
            color: colors.mutedForeground,
            size: 28,
            iconSize: AppIconSizes.sm,
            radius: AppRadius.sm,
            backgroundOpacity: AppOpacity.subtle,
            foregroundOpacity: 1,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.captionLabelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  value,
                  style: context.labelStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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
