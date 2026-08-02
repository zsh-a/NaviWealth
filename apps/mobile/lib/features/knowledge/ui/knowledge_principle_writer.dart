part of '_object_writers.dart';

class _PrincipleWriter extends ConsumerStatefulWidget {
  const _PrincipleWriter({this.initial, required this.dirty});
  final KnowledgePrinciple? initial;
  final FormDirtyController dirty;
  @override
  ConsumerState<_PrincipleWriter> createState() => _PrincipleWriterState();
}

class _PrincipleWriterState extends ConsumerState<_PrincipleWriter> {
  late final _stmtCtrl = TextEditingController(
    text: widget.initial?.statement ?? '',
  );
  late final _rationaleCtrl = TextEditingController(
    text: widget.initial?.rationaleMd ?? '',
  );
  late final _scopeCtrl = TextEditingController(
    text: widget.initial?.scope ?? '*',
  );
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stmtCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    widget.dirty.bindTextControllers([_stmtCtrl, _rationaleCtrl, _scopeCtrl]);
  }

  @override
  void dispose() {
    _stmtCtrl.dispose();
    _rationaleCtrl.dispose();
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
      await repo.upsertPrinciple(
        KnowledgePrinciple(
          id: existing?.id ?? kKnowledgeUuid.v4(),
          statement: _stmtCtrl.text.trim(),
          rationaleMd: _rationaleCtrl.text,
          scope: _scopeCtrl.text.trim().isEmpty ? '*' : _scopeCtrl.text.trim(),
          status: existing?.status ?? PrincipleStatus.active,
          declaredAt: existing?.declaredAt ?? stamp.now,
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
      title: l10n.knowledgePrincipleWriterTitle,
      subtitle: l10n.knowledgePrincipleWriterSubtitle,
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
                hint: l10n.knowledgePrincipleStatementHint,
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
                controller: _rationaleCtrl,
                label: l10n.knowledgeWriterRationaleMarkdownLabel,
                hint: l10n.knowledgePrincipleRationaleHint,
                minLines: 2,
                maxLines: 4,
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _scopeCtrl),
                label: Text(l10n.knowledgeWriterScopeLabel),
                hint: '"*" / "investing" / "life"',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
