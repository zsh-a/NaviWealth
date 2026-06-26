import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';

Future<bool?> showExecutionCommitmentSheet({
  required BuildContext context,
  required WidgetRef ref,
}) {
  return showAppSheet<bool>(
    context: context,
    title: AppLocalizations.of(context).executionCreateCommitmentTitle,
    builder: (_) => _ExecutionCommitmentForm(ref: ref),
  );
}

class _ExecutionCommitmentForm extends StatefulWidget {
  const _ExecutionCommitmentForm({required this.ref});

  final WidgetRef ref;

  @override
  State<_ExecutionCommitmentForm> createState() =>
      _ExecutionCommitmentFormState();
}

class _ExecutionCommitmentFormState extends State<_ExecutionCommitmentForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
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
    final title = _title.text.trim();
    setState(() => _saving = true);
    try {
      final repo = await widget.ref.read(executionRepositoryProvider.future);
      final sync = await stampExecutionSync(widget.ref);
      await repo.upsertCommitment(_buildCommitment(sync, title));
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ExecutionCommitment _buildCommitment(SyncMeta sync, String title) {
    return ExecutionCommitment(
      id: kExecutionUuid.v4(),
      title: title,
      description: _description.text.trim(),
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
          hint: l10n.executionCommitmentTitleHint,
          maxLines: 1,
        ),
        const SizedBox(height: AppSpacing.s12),
        FTextField(
          control: FTextFieldControl.managed(controller: _description),
          hint: l10n.executionCommitmentDescriptionHint,
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
            AppBusyButton(
              label: l10n.commonSave,
              busyLabel: l10n.commonSaving,
              busy: _saving,
              onPress: _canSave ? _save : null,
            ),
          ],
        ),
      ],
    );
  }
}
