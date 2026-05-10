import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/corporate_action_preview.dart';
import '../domain/cost_basis/fifo_strategy.dart';
import '../domain/cost_basis_engine.dart';
import '../domain/models/corporate_actions.dart';
import '../domain/models/lot.dart';

/// One asset shown in the picker.
class CorporateActionAsset {
  const CorporateActionAsset({
    required this.id,
    required this.displayName,
    required this.accountId,
    required this.currency,
  });

  final String id;
  final String displayName;
  final String accountId;
  final String currency;
}

/// The five corporate-action event types the form supports.
enum CorporateActionType {
  cashDividend,
  stockDividend,
  split,
  rightsIssue,
  drip,
}

/// Form-as-page for recording a corporate action against an existing
/// holding. The page is pure — no Drift, no Riverpod — so it can be wired
/// into either a stub demo route or a real persistence layer once it
/// exists. Caller supplies:
///
/// - [assets]: dropdown options (id, accountId, display name, currency).
/// - [lotsForAsset]: returns the open lots used to compute the preview.
/// - [onSubmit]: invoked with the engine's [CorporateActionPreview] when the
///   user taps "Submit". The page does not persist anything itself.
///
/// Optional injection points for tests:
/// - [engine]: defaults to `CostBasisEngine(strategy: FifoStrategy())`.
/// - [now]: used as the default effective date.
/// - [idGenerator]: used to seed transaction ids so widget tests can assert
///   on stable IDs.
class CorporateActionEntryPage extends StatefulWidget {
  const CorporateActionEntryPage({
    super.key,
    required this.assets,
    required this.lotsForAsset,
    required this.onSubmit,
    this.engine,
    this.now,
    this.idGenerator,
  });

  final List<CorporateActionAsset> assets;
  final List<Lot> Function(String assetId) lotsForAsset;
  final void Function(CorporateActionPreview preview) onSubmit;

  final CostBasisEngine? engine;
  final DateTime? now;
  final String Function()? idGenerator;

  @override
  State<CorporateActionEntryPage> createState() =>
      _CorporateActionEntryPageState();
}

class _CorporateActionEntryPageState extends State<CorporateActionEntryPage> {
  final _formKey = GlobalKey<FormState>();

  late CostBasisEngine _engine;
  late int _txCounter;
  late DateTime _effectiveDate;

  CorporateActionAsset? _selectedAsset;
  CorporateActionType _type = CorporateActionType.cashDividend;
  CorporateActionPreview? _preview;
  String? _previewError;

  // Per-type controllers. Only the ones for the active type are read.
  final _amountPerShareCtl = TextEditingController();
  final _withholdingTaxCtl = TextEditingController(text: '0');
  final _bonusRatioCtl = TextEditingController();
  final _splitRatioCtl = TextEditingController();
  final _subscribedQtyCtl = TextEditingController();
  final _pricePerUnitCtl = TextEditingController();
  final _feeCtl = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? CostBasisEngine(strategy: const FifoStrategy());
    _effectiveDate = widget.now ?? DateTime.now();
    _txCounter = 0;
    _selectedAsset = widget.assets.isEmpty ? null : widget.assets.first;
  }

  @override
  void dispose() {
    _amountPerShareCtl.dispose();
    _withholdingTaxCtl.dispose();
    _bonusRatioCtl.dispose();
    _splitRatioCtl.dispose();
    _subscribedQtyCtl.dispose();
    _pricePerUnitCtl.dispose();
    _feeCtl.dispose();
    super.dispose();
  }

  String _nextTxId() {
    final gen = widget.idGenerator;
    if (gen != null) return gen();
    _txCounter++;
    final ts = _effectiveDate.millisecondsSinceEpoch;
    return 'corp-$ts-$_txCounter';
  }

  void _onTypeChanged(CorporateActionType? next) {
    if (next == null) return;
    setState(() {
      _type = next;
      _preview = null;
      _previewError = null;
    });
  }

  void _onAssetChanged(CorporateActionAsset? next) {
    if (next == null) return;
    setState(() {
      _selectedAsset = next;
      _preview = null;
      _previewError = null;
    });
  }

  Future<void> _pickEffectiveDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _effectiveDate = DateTime.utc(picked.year, picked.month, picked.day);
        _preview = null;
      });
    }
  }

  CorporateAction _buildAction(CorporateActionAsset asset) {
    final txId = _nextTxId();
    switch (_type) {
      case CorporateActionType.cashDividend:
        return CashDividendAction(
          id: txId,
          assetId: asset.id,
          effectiveDate: _effectiveDate,
          transactionId: txId,
          accountId: asset.accountId,
          currency: asset.currency,
          amountPerShare: Decimal.parse(_amountPerShareCtl.text.trim()),
          withholdingTax: _decOrZero(_withholdingTaxCtl.text),
        );
      case CorporateActionType.stockDividend:
        return StockDividendAction(
          id: txId,
          assetId: asset.id,
          effectiveDate: _effectiveDate,
          bonusRatio: Decimal.parse(_bonusRatioCtl.text.trim()),
        );
      case CorporateActionType.split:
        return SplitAction(
          id: txId,
          assetId: asset.id,
          effectiveDate: _effectiveDate,
          ratio: Decimal.parse(_splitRatioCtl.text.trim()),
        );
      case CorporateActionType.rightsIssue:
        return RightsIssueAction(
          id: txId,
          assetId: asset.id,
          effectiveDate: _effectiveDate,
          transactionId: txId,
          accountId: asset.accountId,
          currency: asset.currency,
          subscribedQuantity: Decimal.parse(_subscribedQtyCtl.text.trim()),
          pricePerUnit: Decimal.parse(_pricePerUnitCtl.text.trim()),
          fee: _decOrZero(_feeCtl.text),
        );
      case CorporateActionType.drip:
        return DripAction(
          id: txId,
          assetId: asset.id,
          effectiveDate: _effectiveDate,
          transactionId: txId,
          accountId: asset.accountId,
          currency: asset.currency,
          amountPerShare: Decimal.parse(_amountPerShareCtl.text.trim()),
          pricePerUnit: Decimal.parse(_pricePerUnitCtl.text.trim()),
          withholdingTax: _decOrZero(_withholdingTaxCtl.text),
          fee: _decOrZero(_feeCtl.text),
        );
    }
  }

  Decimal _decOrZero(String s) {
    final t = s.trim();
    if (t.isEmpty) return Decimal.zero;
    return Decimal.parse(t);
  }

  void _runPreview() {
    final asset = _selectedAsset;
    if (asset == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      final lots = widget.lotsForAsset(asset.id);
      final action = _buildAction(asset);
      final preview = CorporateActionPreview.compute(
        engine: _engine,
        action: action,
        startingLots: lots,
      );
      setState(() {
        _preview = preview;
        _previewError = null;
      });
    } on ArgumentError catch (e) {
      setState(() {
        _preview = null;
        _previewError = e.message?.toString() ?? e.toString();
      });
    }
  }

  void _submit() {
    final preview = _preview;
    if (preview == null) return;
    widget.onSubmit(preview);
    Haptics.success();
    final l10n = AppLocalizations.of(context);
    if (mounted) {
      AppMessenger.show(context, ToastKind.success, l10n.corpActionSubmitted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final dateFmt = DateFormat.yMd(Localizations.localeOf(context).toString());
    final asset = _selectedAsset;

    return FScaffold(
      header: FHeader.nested(title: Text(l10n.corpActionTitle), prefixes: [backHeaderAction(context)]),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Asset picker.
                FSelect<CorporateActionAsset>(
                  key: const Key('corp-action-asset'),
                  items: {for (final a in widget.assets) a.displayName: a},
                  control: FSelectControl<CorporateActionAsset>.managed(
                    initial: asset,
                    onChange: _onAssetChanged,
                  ),
                  label: Text(l10n.corpActionSelectAsset),
                  description: Text(l10n.corpActionSelectAssetHint),
                ),
                const SizedBox(height: 16),
                // Effective date row.
                FTile(
                  key: const Key('corp-action-date'),
                  title: Text(l10n.corpActionEffectiveDate),
                  prefix: const Icon(Icons.event),
                  subtitle: Text(dateFmt.format(_effectiveDate)),
                  suffix: FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: _pickEffectiveDate,
                    child: const Icon(Icons.edit_calendar, size: 20),
                  ),
                ),
                const FDivider(),
                // Event type selector.
                Text(
                  l10n.corpActionEventTypeTitle,
                  style: context.theme.typography.md,
                ),
                const SizedBox(height: 8),
                _TypeSelector(
                  selected: _type,
                  onChanged: _onTypeChanged,
                  l10n: l10n,
                ),
                const SizedBox(height: 16),
                // Type-specific fields.
                ..._fieldsForType(l10n),
                const SizedBox(height: 24),
                // Action buttons.
                Row(
                  children: [
                    FButton(
                      key: const Key('corp-action-preview'),
                      variant: FButtonVariant.outline,
                      onPress: asset == null ? null : _runPreview,
                      child: Text(l10n.corpActionPreviewAction),
                    ),
                    const SizedBox(width: 12),
                    FButton(
                      key: const Key('corp-action-submit'),
                      variant: FButtonVariant.primary,
                      onPress: _preview == null ? null : _submit,
                      child: Text(l10n.corpActionSubmitAction),
                    ),
                  ],
                ),
                if (_previewError != null) ...[
                  const SizedBox(height: 16),
                  FCard.raw(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _previewError!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_preview != null) ...[
                  const SizedBox(height: 16),
                  _PreviewCard(
                    key: const Key('corp-action-preview-card'),
                    preview: _preview!,
                    l10n: l10n,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _fieldsForType(AppLocalizations l10n) {
    switch (_type) {
      case CorporateActionType.cashDividend:
        return [
          _decimalField(
            controllerKey: 'amount-per-share',
            controller: _amountPerShareCtl,
            label: l10n.corpActionAmountPerShare,
            requirePositive: false,
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _decimalField(
            controllerKey: 'withholding-tax',
            controller: _withholdingTaxCtl,
            label: l10n.corpActionWithholdingTax,
            requirePositive: false,
            l10n: l10n,
          ),
        ];
      case CorporateActionType.stockDividend:
        return [
          _decimalField(
            controllerKey: 'bonus-ratio',
            controller: _bonusRatioCtl,
            label: l10n.corpActionBonusRatio,
            requirePositive: false,
            l10n: l10n,
          ),
        ];
      case CorporateActionType.split:
        return [
          _decimalField(
            controllerKey: 'split-ratio',
            controller: _splitRatioCtl,
            label: l10n.corpActionSplitRatio,
            helper: l10n.corpActionSplitRatioHelp,
            requirePositive: true,
            l10n: l10n,
          ),
        ];
      case CorporateActionType.rightsIssue:
        return [
          _decimalField(
            controllerKey: 'subscribed-qty',
            controller: _subscribedQtyCtl,
            label: l10n.corpActionSubscribedQuantity,
            requirePositive: true,
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _decimalField(
            controllerKey: 'price-per-unit',
            controller: _pricePerUnitCtl,
            label: l10n.corpActionPricePerUnit,
            requirePositive: true,
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _decimalField(
            controllerKey: 'fee',
            controller: _feeCtl,
            label: l10n.corpActionFee,
            requirePositive: false,
            l10n: l10n,
          ),
        ];
      case CorporateActionType.drip:
        return [
          _decimalField(
            controllerKey: 'amount-per-share',
            controller: _amountPerShareCtl,
            label: l10n.corpActionAmountPerShare,
            requirePositive: true,
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _decimalField(
            controllerKey: 'price-per-unit',
            controller: _pricePerUnitCtl,
            label: l10n.corpActionPricePerUnit,
            requirePositive: true,
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _decimalField(
            controllerKey: 'withholding-tax',
            controller: _withholdingTaxCtl,
            label: l10n.corpActionWithholdingTax,
            requirePositive: false,
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _decimalField(
            controllerKey: 'fee',
            controller: _feeCtl,
            label: l10n.corpActionFee,
            requirePositive: false,
            l10n: l10n,
          ),
        ];
    }
  }

  Widget _decimalField({
    required String controllerKey,
    required TextEditingController controller,
    required String label,
    String? helper,
    required bool requirePositive,
    required AppLocalizations l10n,
  }) {
    return FTextFormField(
      key: Key('corp-action-$controllerKey'),
      control: FTextFieldControl.managed(controller: controller),
      label: Text(label),
      description: helper == null ? null : Text(helper),
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
      validator: (value) =>
          _validateDecimal(value, requirePositive: requirePositive, l10n: l10n),
    );
  }

  String? _validateDecimal(
    String? raw, {
    required bool requirePositive,
    required AppLocalizations l10n,
  }) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) {
      return requirePositive
          ? l10n.corpActionInvalidNumber
          : l10n.corpActionInvalidNumberNonNegative;
    }
    Decimal? parsed;
    try {
      parsed = Decimal.parse(text);
    } catch (_) {
      return requirePositive
          ? l10n.corpActionInvalidNumber
          : l10n.corpActionInvalidNumberNonNegative;
    }
    if (requirePositive && parsed.sign <= 0) {
      return l10n.corpActionInvalidNumber;
    }
    if (!requirePositive && parsed.sign < 0) {
      return l10n.corpActionInvalidNumberNonNegative;
    }
    return null;
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.selected,
    required this.onChanged,
    required this.l10n,
  });

  final CorporateActionType selected;
  final ValueChanged<CorporateActionType?> onChanged;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final entries = <(CorporateActionType, String)>[
      (CorporateActionType.cashDividend, l10n.corpActionTypeCashDividend),
      (CorporateActionType.stockDividend, l10n.corpActionTypeStockDividend),
      (CorporateActionType.split, l10n.corpActionTypeSplit),
      (CorporateActionType.rightsIssue, l10n.corpActionTypeRightsIssue),
      (CorporateActionType.drip, l10n.corpActionTypeDrip),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (type, label) in entries)
          FButton(
            key: Key('corp-action-type-${type.name}'),
            variant: (selected == type)
                ? FButtonVariant.primary
                : FButtonVariant.outline,
            onPress: () => onChanged(type),
            child: Text(label),
          ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({super.key, required this.preview, required this.l10n});

  final CorporateActionPreview preview;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final dividend = preview.cashDividend;
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.corpActionPreviewHeading,
              style: context.theme.typography.md,
            ),
            const SizedBox(height: 12),
            if (dividend != null) ...[
              _kv(
                l10n.corpActionPreviewSharesOnRecord,
                '${dividend.shareCount}',
              ),
              _kv(
                l10n.corpActionPreviewGross,
                '${dividend.grossAmount} ${dividend.currency}',
              ),
              _kv(
                l10n.corpActionPreviewTax,
                '${dividend.withholdingTax} ${dividend.currency}',
              ),
              _kv(
                l10n.corpActionPreviewNet,
                '${dividend.netAmount} ${dividend.currency}',
              ),
            ] else if (preview.action is CashDividendAction)
              Text(l10n.corpActionNoEligibleHolding),
            if (preview.cashFlow != Decimal.zero)
              _kv(
                l10n.corpActionPreviewCashFlow,
                '${preview.cashFlow} ${preview.cashFlowCurrency}',
              ),
            for (final delta in preview.lotDeltas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l10n.corpActionPreviewLotChange(
                    delta.before.id,
                    '${delta.before.remainingQuantity}',
                    '${delta.after.remainingQuantity}',
                    '${delta.before.costPerUnit}',
                    '${delta.after.costPerUnit}',
                  ),
                ),
              ),
            for (final newLot in preview.newLots)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l10n.corpActionPreviewNewLot(
                    '${newLot.originalQuantity}',
                    '${newLot.costPerUnit}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text(value)],
    ),
  );
}
