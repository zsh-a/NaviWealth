import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';

Future<bool?> showExecutionActionSheet({
  required BuildContext context,
  required WidgetRef ref,
}) {
  return showAppSheet<bool>(
    context: context,
    title: AppLocalizations.of(context).executionCreateActionTitle,
    builder: (_) => _ExecutionActionForm(ref: ref),
  );
}

class _ExecutionActionForm extends StatefulWidget {
  const _ExecutionActionForm({required this.ref});

  final WidgetRef ref;

  @override
  State<_ExecutionActionForm> createState() => _ExecutionActionFormState();
}

class _ExecutionActionFormState extends State<_ExecutionActionForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = await widget.ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(widget.ref);
      await repo.upsertAction(_buildAction(sync, title));
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ExecutionAction _buildAction(SyncMeta sync, String title) {
    return ExecutionAction(
      id: kExecutionUuid.v4(),
      title: title,
      note: _note.text.trim(),
      createdAt: sync.updatedAt,
      sync: sync,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FTextField(
          control: FTextFieldControl.managed(controller: _title),
          hint: l10n.executionActionTitleHint,
          maxLines: 1,
        ),
        const SizedBox(height: AppSpacing.s12),
        FTextField(
          control: FTextFieldControl.managed(controller: _note),
          hint: l10n.executionActionNoteHint,
          minLines: 3,
          maxLines: 5,
        ),
        const SizedBox(height: AppSpacing.s16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FButton(
              variant: FButtonVariant.outline,
              onPress: _saving ? null : () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            const SizedBox(width: AppSpacing.s8),
            FButton(
              onPress: _saving ? null : _save,
              child: Text(_saving ? l10n.commonSaving : l10n.commonSave),
            ),
          ],
        ),
      ],
    );
  }
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
