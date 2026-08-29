import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

enum _CaptureType { note, decision }

Future<void> showKnowledgeCaptureSheet(BuildContext context) {
  return showAppFormSheet<void>(
    context: context,
    builder: (_) => const _KnowledgeCaptureSheet(),
  );
}

class _KnowledgeCaptureSheet extends ConsumerStatefulWidget {
  const _KnowledgeCaptureSheet();

  @override
  ConsumerState<_KnowledgeCaptureSheet> createState() =>
      _KnowledgeCaptureSheetState();
}

class _KnowledgeCaptureSheetState
    extends ConsumerState<_KnowledgeCaptureSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _selected = TextEditingController();
  final _tags = TextEditingController();
  var _type = _CaptureType.note;
  var _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _selected.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.knowledgeCaptureTitle,
      footer: AppSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        onSubmit: _save,
        busy: _saving,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedRow<_CaptureType>(
            options: _CaptureType.values,
            value: _type,
            labelOf: (value) => switch (value) {
              _CaptureType.note => l10n.knowledgeSegmentNotes,
              _CaptureType.decision => l10n.knowledgeSegmentDecisions,
            },
            onChanged: _saving
                ? (_) {}
                : (value) => setState(() => _type = value),
          ),
          const SizedBox(height: AppSpacing.s16),
          FTextField(
            control: FTextFieldControl.managed(controller: _title),
            autofocus: true,
            textInputAction: TextInputAction.next,
            label: Text(
              _type == _CaptureType.note
                  ? l10n.knowledgeCaptureTitleField
                  : l10n.knowledgeDecisionQuestionLabel,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          if (_type == _CaptureType.decision) ...[
            FTextField(
              control: FTextFieldControl.managed(controller: _selected),
              label: Text(l10n.knowledgeDecisionOptionsLabel),
              hint: l10n.knowledgeDecisionSelectionRequirement,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          FTextField(
            control: FTextFieldControl.managed(controller: _body),
            minLines: 4,
            maxLines: 10,
            label: Text(
              _type == _CaptureType.note
                  ? l10n.knowledgeCaptureBodyField
                  : l10n.knowledgeWriterRationaleMarkdownLabel,
            ),
          ),
          if (_type == _CaptureType.note) ...[
            const SizedBox(height: AppSpacing.s12),
            FTextField(
              control: FTextFieldControl.managed(controller: _tags),
              label: Text(l10n.knowledgeNoteTagsLabel),
              hint: l10n.knowledgeNoteTagsHint,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    final selected = _selected.text.trim();
    if ((_type == _CaptureType.note && title.isEmpty && body.isEmpty) ||
        (_type == _CaptureType.decision &&
            (title.isEmpty || selected.isEmpty))) {
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final value = await stamper.stamp();
      final sync = SyncMeta(
        ownerUserId: value.ownerUserId,
        updatedAt: value.now,
        updatedByDevice: value.deviceId,
        hlc: value.hlc,
      );
      if (_type == _CaptureType.note) {
        await repository.upsertNote(
          KnowledgeNote(
            id: kKnowledgeUuid.v4(),
            title: title,
            bodyMd: body,
            tags: _tags.text
                .split(RegExp(r'[,，\s]+'))
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(growable: false),
            createdAt: value.now,
            sync: sync,
          ),
        );
      } else {
        await repository.upsertDecision(
          KnowledgeDecision(
            id: kKnowledgeUuid.v4(),
            question: title,
            options: <DecisionOption>[DecisionOption(label: selected)],
            selectedLabel: selected,
            rationaleMd: body,
            status: DecisionStatus.active,
            decidedAt: value.now,
            sync: sync,
          ),
        );
      }
      ref.invalidate(knowledgeNotesProvider);
      ref.invalidate(knowledgeDecisionsProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
