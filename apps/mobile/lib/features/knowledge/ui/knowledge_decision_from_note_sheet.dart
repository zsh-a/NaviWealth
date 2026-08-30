import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/knowledge_decision_from_note_service.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';
import 'widgets/knowledge_markdown_editor.dart';

Future<String?> showKnowledgeDecisionFromNoteSheet({
  required BuildContext context,
  required KnowledgeNote note,
}) {
  return showAppFormSheet<String>(
    context: context,
    builder: (_) => _KnowledgeDecisionFromNoteSheet(note: note),
  );
}

class _KnowledgeDecisionFromNoteSheet extends ConsumerStatefulWidget {
  const _KnowledgeDecisionFromNoteSheet({required this.note});

  final KnowledgeNote note;

  @override
  ConsumerState<_KnowledgeDecisionFromNoteSheet> createState() =>
      _KnowledgeDecisionFromNoteSheetState();
}

class _KnowledgeDecisionFromNoteSheetState
    extends ConsumerState<_KnowledgeDecisionFromNoteSheet> {
  final _question = TextEditingController();
  final _selected = TextEditingController();
  final _rationale = TextEditingController();
  var _saving = false;
  String? _error;

  bool get _canSave =>
      _question.text.trim().isNotEmpty && _selected.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _question.addListener(_refreshValidation);
    _selected.addListener(_refreshValidation);
  }

  void _refreshValidation() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _question.dispose();
    _selected.dispose();
    _rationale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final noteTitle = widget.note.title.isEmpty
        ? l10n.knowledgeUntitled
        : widget.note.title;
    final excerpt = knowledgeExcerpt(
      widget.note.bodyMd,
      max: kKnowledgeHeadlineExcerptMaxChars,
    );
    return AppSheet(
      title: l10n.knowledgeCreateDecisionFromNoteTitle,
      subtitle: l10n.knowledgeDecisionSourceNote,
      footer: AppSheetFooter(
        submitKey: const Key('knowledge-decision-from-note-submit'),
        submitLabel: l10n.knowledgeCreateDecisionAction,
        cancelLabel: l10n.commonCancel,
        enabled: _canSave,
        busy: _saving,
        onSubmit: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoftCard.flat(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Row(
              children: [
                const Icon(FLucideIcons.fileText, size: AppIconSizes.sm),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(noteTitle, style: context.labelStyle),
                      if (excerpt.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          excerpt,
                          style: context.captionStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          FTextField(
            key: const Key('knowledge-decision-from-note-question'),
            control: FTextFieldControl.managed(controller: _question),
            autofocus: true,
            label: Text(l10n.knowledgeDecisionQuestionLabel),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            key: const Key('knowledge-decision-from-note-selection'),
            control: FTextFieldControl.managed(controller: _selected),
            label: Text(l10n.knowledgeDecisionOptionsLabel),
            hint: l10n.knowledgeDecisionSelectionRequirement,
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeMarkdownEditor(
            controller: _rationale,
            label: l10n.knowledgeWriterRationaleMarkdownLabel,
            minLines: 4,
            maxLines: 8,
            enabled: !_saving,
          ),
          if (_error case final message?) ...[
            const SizedBox(height: AppSpacing.s10),
            Text(
              message,
              style: context.captionStyle.copyWith(
                color: context.theme.colors.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = await ref.read(
        knowledgeDecisionFromNoteServiceProvider.future,
      );
      final decision = await service.create(
        noteId: widget.note.id,
        question: _question.text,
        selectedLabel: _selected.text,
        rationaleMd: _rationale.text,
      );
      ref.invalidate(knowledgeDecisionsProvider);
      if (mounted) Navigator.of(context).pop(decision.id);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = userSafeErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
