part of '_object_writers.dart';

class _AssumptionWriter extends ConsumerStatefulWidget {
  const _AssumptionWriter({this.initial});
  final KnowledgeAssumption? initial;
  @override
  ConsumerState<_AssumptionWriter> createState() => _AssumptionWriterState();
}

class _AssumptionWriterState extends ConsumerState<_AssumptionWriter> {
  late final _stmtCtrl = TextEditingController(
    text: widget.initial?.statement ?? '',
  );
  late final _scopeCtrl = TextEditingController(
    text: widget.initial?.scope ?? '*',
  );
  late double _confidence = widget.initial?.confidence ?? 0.7;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stmtCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stmtCtrl.dispose();
    _scopeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _stmtCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final existing = widget.initial;
      await repo.upsertAssumption(
        KnowledgeAssumption(
          id: existing?.id ?? kKnowledgeUuid.v4(),
          statement: _stmtCtrl.text.trim(),
          confidence: _confidence,
          scope: _scopeCtrl.text.trim().isEmpty ? '*' : _scopeCtrl.text.trim(),
          evidenceIds: existing?.evidenceIds ?? const <String>[],
          status: existing?.status ?? AssumptionStatus.active,
          declaredAt: existing?.declaredAt ?? stamp.now,
          lastVerifiedAt: existing?.lastVerifiedAt,
          mergedIntoId: existing?.mergedIntoId,
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
      title: l10n.knowledgeAssumptionWriterTitle,
      subtitle: l10n.knowledgeAssumptionWriterSubtitle2,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving || _stmtCtrl.text.trim().isEmpty,
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
                control: FTextFieldControl.managed(controller: _stmtCtrl),
                label: Text(l10n.knowledgeWriterStatementLabel),
                hint: l10n.knowledgeAssumptionStatementHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterEvidenceSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              SegmentedRow<double>(
                options: const <double>[0.3, 0.7, 0.95],
                value: _confidencePresetValue(_confidence),
                labelOf: (value) => switch (value) {
                  0.3 => l10n.knowledgeConfidenceLow,
                  0.7 => l10n.knowledgeConfidenceMedium,
                  _ => l10n.knowledgeConfidenceHigh,
                },
                onChanged: (v) => setState(() => _confidence = v),
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _scopeCtrl),
                label: Text(l10n.knowledgeWriterScopeLabel),
                hint: l10n.knowledgeWriterScopeHint,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

double _confidencePresetValue(double confidence) {
  if (confidence < 0.5) return 0.3;
  if (confidence < 0.85) return 0.7;
  return 0.95;
}
