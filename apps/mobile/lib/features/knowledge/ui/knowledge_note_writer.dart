part of '_object_writers.dart';

class _NoteWriter extends ConsumerStatefulWidget {
  const _NoteWriter({required this.initial, required this.dirty});
  final KnowledgeNote initial;
  final FormDirtyController dirty;
  @override
  ConsumerState<_NoteWriter> createState() => _NoteWriterState();
}

class _NoteWriterState extends ConsumerState<_NoteWriter> {
  late final _titleCtrl = TextEditingController(text: widget.initial.title);
  late final _bodyCtrl = TextEditingController(text: widget.initial.bodyMd);
  late final _sourceUrlCtrl = TextEditingController(
    text: widget.initial.sourceUrl ?? '',
  );
  late final _tagsCtrl = TextEditingController(
    text: widget.initial.tags.join(', '),
  );
  late final _projectTagCtrl = TextEditingController(
    text: widget.initial.projectTag ?? '',
  );
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    widget.dirty.bindTextControllers([
      _titleCtrl,
      _bodyCtrl,
      _sourceUrlCtrl,
      _tagsCtrl,
      _projectTagCtrl,
    ]);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _sourceUrlCtrl.dispose();
    _tagsCtrl.dispose();
    _projectTagCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final tags = _tagsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      await repo.upsertNote(
        KnowledgeNote(
          id: widget.initial.id,
          title: _titleCtrl.text.trim(),
          bodyMd: _bodyCtrl.text,
          sourceUrl: _sourceUrlCtrl.text.trim().isEmpty
              ? null
              : _sourceUrlCtrl.text.trim(),
          tags: tags,
          projectTag: _projectTagCtrl.text.trim().isEmpty
              ? null
              : _projectTagCtrl.text.trim(),
          createdAt: widget.initial.createdAt,
          mergedIntoId: widget.initial.mergedIntoId,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).commonSaveFailed,
        );
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.knowledgeNoteEditTitle,
      subtitle: l10n.knowledgeNoteEditSubtitle,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving,
        onSubmit: _save,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterCoreSectionTitle,
            children: [
              FTextField(
                control: FTextFieldControl.managed(controller: _titleCtrl),
                label: Text(l10n.knowledgeCaptureTitleField),
                hint: l10n.knowledgeCaptureTitleHint,
              ),
              MarkdownEditorWithPreview(
                controller: _bodyCtrl,
                label: l10n.knowledgeCaptureBodyField,
                hint: l10n.knowledgeCaptureBodyHint,
                minLines: 4,
                maxLines: 8,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterEvidenceSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              FTextField(
                control: FTextFieldControl.managed(controller: _sourceUrlCtrl),
                label: Text(l10n.knowledgeNoteSourceUrlLabel),
                hint: 'https://...',
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _tagsCtrl),
                label: Text(l10n.knowledgeWriterAliasLabel),
                hint: l10n.knowledgeNoteTagsHint,
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _projectTagCtrl),
                label: Text(l10n.knowledgeDetailProjectLabel),
                hint: l10n.knowledgeNoteProjectHint,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
