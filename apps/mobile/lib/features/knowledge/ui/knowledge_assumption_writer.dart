part of '_object_writers.dart';

class _AssumptionWriter extends ConsumerStatefulWidget {
  const _AssumptionWriter({this.initial, required this.dirty});
  final KnowledgeAssumption? initial;
  final FormDirtyController dirty;
  @override
  ConsumerState<_AssumptionWriter> createState() => _AssumptionWriterState();
}

class _AssumptionWriterState extends ConsumerState<_AssumptionWriter> {
  late final _stmtCtrl = TextEditingController(
    text: widget.initial?.statement ?? '',
  );
  late final _scopeCtrl = TextEditingController(
    text: widget.initial?.scope == '*' ? '' : widget.initial?.scope ?? '',
  );
  late double _confidence = widget.initial?.confidence ?? 0.7;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stmtCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    widget.dirty.bindTextControllers([_stmtCtrl, _scopeCtrl]);
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
    widget.dirty.busy = true;
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
    final editing = widget.initial != null;
    return AppSheet(
      title: editing
          ? l10n.knowledgeAssumptionEditTitle
          : l10n.knowledgeAssumptionWriterTitle,
      subtitle: editing
          ? l10n.knowledgeAssumptionEditSubtitle
          : l10n.knowledgeAssumptionWriterSubtitle2,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving,
        enabled: _stmtCtrl.text.trim().isNotEmpty,
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
              Text(
                l10n.knowledgeWriterConfidenceLabel,
                style: context.captionLabelStyle,
              ),
              SegmentedRow<double>(
                options: const <double>[0.3, 0.7, 0.95],
                value: _confidencePresetValue(_confidence),
                labelOf: (value) => switch (value) {
                  0.3 => l10n.knowledgeConfidenceLow,
                  0.7 => l10n.knowledgeConfidenceMedium,
                  _ => l10n.knowledgeConfidenceHigh,
                },
                onChanged: (v) {
                  setState(() => _confidence = v);
                  widget.dirty.markDirty();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterContextSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
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
