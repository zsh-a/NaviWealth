part of '../ingest_review_page.dart';

class _IngestDraftEditSheet extends ConsumerStatefulWidget {
  const _IngestDraftEditSheet({
    required this.drafts,
    required this.initialId,
    required this.dirty,
    required this.onCurrentChanged,
  });

  final List<IngestDraft> drafts;
  final String initialId;
  final FormDirtyController dirty;
  final ValueChanged<String> onCurrentChanged;

  @override
  ConsumerState<_IngestDraftEditSheet> createState() =>
      _IngestDraftEditSheetState();
}

class _IngestDraftEditSheetState extends ConsumerState<_IngestDraftEditSheet> {
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _category;
  late DateTime _date;
  late IngestTransactionKind _kind;
  String? _error;
  late IngestDraft _draft;
  late int _index;
  bool _working = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _index = widget.drafts.indexWhere(
      (draft) => draft.draftId == widget.initialId,
    );
    _draft = widget.drafts[_index];
    final parsed = _draft.parsed;
    _description = TextEditingController(text: parsed.description);
    _amount = TextEditingController(
      text: formatAbsoluteMinorUnitAmount(parsed.amountMinor),
    );
    _currency = TextEditingController(text: parsed.currency);
    _category = TextEditingController(text: parsed.categoryHint);
    _date = parsed.occurredAt;
    _kind = parsed.kind;
    widget.dirty.bindTextControllers([
      _description,
      _amount,
      _currency,
      _category,
    ]);
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _currency.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.ingestEditDraft,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.drafts.length > 1) ...[
            Row(
              children: [
                AppIconButton(
                  tooltip: l10n.ingestPreviousDraft,
                  onPress: _working || _index == 0 ? null : () => _navigate(-1),
                  icon: FLucideIcons.chevronLeft,
                ),
                Expanded(
                  child: Text(
                    l10n.ingestReviewPosition(_index + 1, widget.drafts.length),
                    textAlign: TextAlign.center,
                    style: context.bodyCaptionStyle,
                  ),
                ),
                AppIconButton(
                  tooltip: l10n.ingestNextDraft,
                  onPress: _working || _index == widget.drafts.length - 1
                      ? null
                      : () => _navigate(1),
                  icon: FLucideIcons.chevronRight,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          AppSheetFooter(
            submitLabel: l10n.commonSave,
            cancelLabel: l10n.commonCancel,
            onSubmit: () => _save(advance: false),
            busy: _working,
          ),
          if (_index < widget.drafts.length - 1) ...[
            const SizedBox(height: AppSpacing.s8),
            AppActionButton(
              key: const ValueKey('ingest-save-next'),
              variant: FButtonVariant.outline,
              onPress: _working ? null : () => _save(advance: true),
              child: Flexible(child: Text(l10n.ingestSaveAndNext)),
            ),
          ],
        ],
      ),
      child: AbsorbPointer(
        absorbing: _working,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppAdaptiveChoice<IngestTransactionKind>(
              title: l10n.ingestEditDraft,
              options: IngestTransactionKind.values,
              value: _kind,
              labelOf: (kind) => switch (kind) {
                IngestTransactionKind.income => l10n.ingestKindIncome,
                IngestTransactionKind.expense => l10n.ingestKindExpense,
                IngestTransactionKind.transfer => l10n.ingestKindTransfer,
                IngestTransactionKind.trade => l10n.ingestKindTrade,
              },
              iconOf: (kind) => switch (kind) {
                IngestTransactionKind.income => FLucideIcons.arrowDownLeft,
                IngestTransactionKind.expense => FLucideIcons.arrowUpRight,
                IngestTransactionKind.transfer => FLucideIcons.arrowRightLeft,
                IngestTransactionKind.trade => FLucideIcons.chartCandlestick,
              },
              onChanged: (kind) {
                if (kind == _kind) return;
                widget.dirty.markDirty();
                setState(() => _kind = kind);
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextField(
              control: FTextFieldControl.managed(controller: _description),
              label: Text(l10n.ingestEditDescription),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextField(
              control: FTextFieldControl.managed(controller: _amount),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: Text(l10n.ingestEditAmount),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextField(
              control: FTextFieldControl.managed(controller: _currency),
              textCapitalization: TextCapitalization.characters,
              label: Text(l10n.ingestEditCurrency),
            ),
            const SizedBox(height: AppSpacing.s12),
            DateField(
              key: ValueKey(_draft.draftId),
              label: l10n.ingestEditDate,
              initialValue: _date,
              firstDate: DateTime(1970),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              required: true,
              onChanged: (value) {
                if (value != null && value != _date) {
                  widget.dirty.markDirty();
                  setState(() => _date = value);
                }
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextField(
              control: FTextFieldControl.managed(controller: _category),
              label: Text(l10n.ingestEditCategory),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s12),
              AppStatusBanner(kind: AppStatusKind.error, message: _error!),
            ],
          ],
        ),
      ),
    );
  }

  ParsedTransaction? _parse() {
    final unsignedMinor = parseUnsignedMinorUnitAmount(_amount.text);
    final currency = _currency.text.trim().toUpperCase();
    final description = _description.text.trim();
    if (unsignedMinor == null ||
        unsignedMinor <= 0 ||
        currency.isEmpty ||
        description.isEmpty) {
      setState(() {
        _error = AppLocalizations.of(context).ingestEditInvalid;
      });
      return null;
    }
    final amountMinor = _kind == IngestTransactionKind.income
        ? unsignedMinor
        : -unsignedMinor;
    return _draft.parsed.copyWith(
      description: description,
      amountMinor: amountMinor,
      currency: currency,
      occurredAt: _date,
      dateHasTime: _date == _draft.parsed.occurredAt
          ? _draft.parsed.dateHasTime
          : false,
      kind: _kind,
      clearCategoryHint: _category.text.trim().isEmpty,
      categoryHint: _category.text.trim().isEmpty
          ? null
          : _category.text.trim(),
    );
  }

  Future<void> _save({required bool advance}) async {
    if (_working) return;
    final parsed = _parse();
    if (parsed == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    widget.dirty.busy = true;
    try {
      final store = ref.read(ingestDraftStoreProvider);
      if (store == null) throw StateError('store unavailable');
      if (_draft.ownerUserId != (store.ownerUserId ?? '')) {
        throw StateError('draft owner changed');
      }
      final updated = await store.updateParsed(
        draftId: _draft.draftId,
        expectedRevision: _draft.revision,
        parsed: parsed,
      );
      if (!mounted) return;
      if (!updated) {
        setState(
          () => _error = AppLocalizations.of(context).ingestEditConflict,
        );
        return;
      }
      widget.dirty.markPristine();
      if (advance && await _loadNext(1)) return;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).ingestEditConflict,
        );
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _navigate(int offset) async {
    if (_working || _navigating) return;
    _navigating = true;
    try {
      if (!await confirmDiscardIfDirty(context, widget.dirty) || !mounted) {
        return;
      }
      setState(() => _working = true);
      widget.dirty.busy = true;
      await _loadNext(offset);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).ingestEditConflict,
        );
      }
    } finally {
      _navigating = false;
      widget.dirty.busy = false;
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _loadNext(int offset) async {
    final store = ref.read(ingestDraftStoreProvider);
    if (store == null) return false;
    for (
      var index = _index + offset;
      index >= 0 && index < widget.drafts.length;
      index += offset
    ) {
      final item = await store.readReviewItem(widget.drafts[index].draftId);
      if (!mounted) return false;
      if (item == null || !item.isOrdinaryPending) continue;
      final parsed = item.draft.parsed;
      setState(() {
        _index = index;
        _draft = item.draft;
        _description.text = parsed.description;
        _amount.text = formatAbsoluteMinorUnitAmount(parsed.amountMinor);
        _currency.text = parsed.currency;
        _category.text = parsed.categoryHint ?? '';
        _date = parsed.occurredAt;
        _kind = parsed.kind;
        _error = null;
      });
      widget.dirty.markPristine();
      widget.onCurrentChanged(item.draft.draftId);
      return true;
    }
    return false;
  }
}

class _IngestCategorySheet extends StatefulWidget {
  const _IngestCategorySheet({required this.count, required this.dirty});
  final int count;
  final FormDirtyController dirty;

  @override
  State<_IngestCategorySheet> createState() => _IngestCategorySheetState();
}

class _IngestCategorySheetState extends State<_IngestCategorySheet> {
  final _category = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.dirty.bindTextControllers([_category]);
  }

  @override
  void dispose() {
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.ingestBatchCategoryCount(widget.count),
      footer: AppSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        onSubmit: () {
          widget.dirty.markPristine();
          Navigator.of(context).pop(_category.text.trim());
        },
      ),
      child: FTextField(
        control: FTextFieldControl.managed(controller: _category),
        label: Text(l10n.ingestEditCategory),
        hint: l10n.ingestCategoryClearHint,
      ),
    );
  }
}
