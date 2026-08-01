part of '../ingest_review_page.dart';

class _IngestDraftEditSheet extends StatefulWidget {
  const _IngestDraftEditSheet({required this.parsed});

  final ParsedTransaction parsed;

  @override
  State<_IngestDraftEditSheet> createState() => _IngestDraftEditSheetState();
}

class _IngestDraftEditSheetState extends State<_IngestDraftEditSheet> {
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _category;
  late DateTime _date;
  late IngestTransactionKind _kind;
  String? _error;

  @override
  void initState() {
    super.initState();
    final parsed = widget.parsed;
    _description = TextEditingController(text: parsed.description);
    _amount = TextEditingController(
      text: formatMinorUnitAmount(parsed.amountMinor.abs()),
    );
    _currency = TextEditingController(text: parsed.currency);
    _category = TextEditingController(text: parsed.categoryHint);
    _date = parsed.occurredAt;
    _kind = parsed.kind;
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
      footer: AppSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        onSubmit: _submit,
      ),
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
            onChanged: (kind) => setState(() => _kind = kind),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _description),
            label: Text(l10n.ingestEditDescription),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _amount),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            label: l10n.ingestEditDate,
            initialValue: _date,
            firstDate: DateTime(1970),
            lastDate: DateTime.now().add(const Duration(days: 1)),
            required: true,
            onChanged: (value) {
              if (value != null) setState(() => _date = value);
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
    );
  }

  void _submit() {
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
      return;
    }
    final amountMinor = _kind == IngestTransactionKind.income
        ? unsignedMinor
        : -unsignedMinor;
    Navigator.of(context).pop(
      widget.parsed.copyWith(
        description: description,
        amountMinor: amountMinor,
        currency: currency,
        occurredAt: _date,
        kind: _kind,
        clearCategoryHint: _category.text.trim().isEmpty,
        categoryHint: _category.text.trim().isEmpty
            ? null
            : _category.text.trim(),
      ),
    );
  }
}
