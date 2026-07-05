part of '_object_writers.dart';

class _ConceptWriter extends ConsumerStatefulWidget {
  const _ConceptWriter({this.initial});
  final KnowledgeConcept? initial;
  @override
  ConsumerState<_ConceptWriter> createState() => _ConceptWriterState();
}

class _ConceptWriterState extends ConsumerState<_ConceptWriter> {
  late final _nameCtrl = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final _aliasesCtrl = TextEditingController(
    text: widget.initial?.aliases.join(', ') ?? '',
  );
  late final _summaryCtrl = TextEditingController(
    text: widget.initial?.summaryMd ?? '',
  );
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _aliasesCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final aliases = _aliasesCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      final existing = widget.initial;
      await repo.upsertConcept(
        KnowledgeConcept(
          id: existing?.id ?? kKnowledgeUuid.v4(),
          name: _nameCtrl.text.trim(),
          aliases: aliases,
          summaryMd: _summaryCtrl.text,
          relatedConceptIds: existing?.relatedConceptIds ?? const <String>[],
          createdAt: existing?.createdAt ?? stamp.now,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.knowledgeConceptWriterTitle,
      subtitle: l10n.knowledgeConceptWriterSubtitle2,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving || _nameCtrl.text.trim().isEmpty,
        onSubmit: () {
          _save();
        },
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterCoreSectionTitle,
            children: [
              FTextField(
                control: FTextFieldControl.managed(controller: _nameCtrl),
                label: Text(l10n.knowledgeWriterNameLabel),
                hint: l10n.knowledgeConceptNameHint,
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _aliasesCtrl),
                label: Text(l10n.knowledgeWriterAliasLabel),
                hint: l10n.knowledgeConceptAliasesHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterEvidenceSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              MarkdownEditorWithPreview(
                controller: _summaryCtrl,
                label: l10n.knowledgeWriterSummaryMarkdownLabel,
                hint: l10n.knowledgeConceptSummaryHint,
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
