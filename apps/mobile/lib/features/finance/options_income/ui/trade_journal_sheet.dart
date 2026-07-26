import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/providers.dart';
import '../domain/options_opportunity.dart';
import '../domain/options_strategy_profile.dart';
import '../domain/trade_journal_entry.dart';
import 'income_planner_labels.dart';

/// Open the trade-journal form sheet.
///
/// Pass [existingId] to edit a row, or [prefilled] to pre-populate the
/// form from an opportunity card. The two are mutually exclusive.
Future<void> showTradeJournalSheet(
  BuildContext context, {
  String? existingId,
  OptionsOpportunity? prefilled,
}) {
  return showGuardedFormSheet(
    context: context,
    builder: (sheetCtx, dirty) => _TradeJournalForm(
      existingId: existingId,
      prefilled: prefilled,
      dirty: dirty,
    ),
  );
}

class _TradeJournalForm extends ConsumerStatefulWidget {
  const _TradeJournalForm({
    required this.dirty,
    this.existingId,
    this.prefilled,
  });

  final String? existingId;
  final OptionsOpportunity? prefilled;
  final FormDirtyController dirty;

  @override
  ConsumerState<_TradeJournalForm> createState() => _TradeJournalFormState();
}

class _TradeJournalFormState extends ConsumerState<_TradeJournalForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _symbolCtl;
  late final TextEditingController _optionSymbolCtl;
  late final TextEditingController _creditCtl;
  late final TextEditingController _debitCtl;
  late final TextEditingController _strikeCtl;
  late final TextEditingController _contractSizeCtl;
  late final TextEditingController _contractQuantityCtl;
  late final TextEditingController _feesCtl;
  late final TextEditingController _notesCtl;

  OptionsStrategyKind _strategy = OptionsStrategyKind.cashSecuredPut;
  TradeJournalStatus _status = TradeJournalStatus.open;
  String _currency = 'USD';
  String? _brokerageAccountId;
  String? _cashAccountId;
  bool _hydratedAccounts = false;
  bool _busy = false;
  TradeJournalEntry? _loaded;
  late DateTime _openedAt;
  DateTime? _expirationAt;
  DateTime? _closedAt;

  @override
  void initState() {
    super.initState();
    final pre = widget.prefilled;
    _symbolCtl = TextEditingController(text: pre?.contract.underlying ?? '');
    _optionSymbolCtl = TextEditingController(
      text: pre?.contract.optionSymbol ?? '',
    );
    _creditCtl = TextEditingController(
      text: pre == null ? '' : pre.metrics.premium.amount.toString(),
    );
    _debitCtl = TextEditingController();
    _strikeCtl = TextEditingController(
      text: pre == null ? '' : pre.contract.strike.amount.toString(),
    );
    _contractSizeCtl = TextEditingController(text: '100');
    _contractQuantityCtl = TextEditingController(text: '1');
    _feesCtl = TextEditingController(text: '0');
    _notesCtl = TextEditingController();
    _openedAt = DateTime.now().toUtc();
    _expirationAt = pre?.contract.expiration;
    if (pre != null) {
      _strategy = pre.strategy;
      _currency = pre.metrics.premium.currency;
    }
    final defaults = ref.read(formDefaultsProvider);
    _brokerageAccountId = defaults.tradeAccountId;
    _cashAccountId = defaults.tradeCashAccountId;
    widget.dirty.bindTextControllers([
      _symbolCtl,
      _optionSymbolCtl,
      _creditCtl,
      _debitCtl,
      _strikeCtl,
      _contractSizeCtl,
      _contractQuantityCtl,
      _feesCtl,
      _notesCtl,
    ]);
    ref.listenManual(accountsStreamProvider, fireImmediately: true, (
      previous,
      next,
    ) {
      final accounts = next.value;
      if (accounts == null || accounts.isEmpty || _hydratedAccounts) return;
      setState(() => _hydrateAccountDefaults(accounts));
    });
    if (widget.existingId != null) {
      unawaited(_loadExisting());
    }
  }

  Future<void> _loadExisting() async {
    final repo = await ref.read(tradeJournalRepositoryProvider.future);
    final entry = await repo.get(widget.existingId!);
    if (!mounted || entry == null) return;
    setState(() {
      _loaded = entry;
      _strategy = entry.strategy;
      _status = entry.status;
      _currency = entry.currency;
      _openedAt = entry.openedAt;
      _expirationAt = entry.expirationAt;
      _closedAt = entry.closedAt;
      _symbolCtl.text = entry.symbol;
      _optionSymbolCtl.text = entry.optionSymbol;
      _creditCtl.text = entry.entryCredit.toString();
      _debitCtl.text = entry.exitDebit?.toString() ?? '';
      _strikeCtl.text = entry.strikePrice?.toString() ?? '';
      _contractSizeCtl.text = (entry.contractSize ?? 100).toString();
      _contractQuantityCtl.text = entry.contractQuantity.toString();
      _feesCtl.text = entry.effectiveFees.toString();
      _notesCtl.text = entry.notes ?? '';
      _brokerageAccountId = entry.brokerageAccountId;
      _cashAccountId = entry.cashAccountId;
    });
    widget.dirty.snapshotBaseline();
  }

  @override
  void dispose() {
    _symbolCtl.dispose();
    _optionSymbolCtl.dispose();
    _creditCtl.dispose();
    _debitCtl.dispose();
    _strikeCtl.dispose();
    _contractSizeCtl.dispose();
    _contractQuantityCtl.dispose();
    _feesCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_status == TradeJournalStatus.assigned &&
        (_brokerageAccountId == null || _brokerageAccountId!.isEmpty)) {
      // Without a brokerage account the assignment share leg cannot be
      // mirrored into the double-entry ledger — refuse instead of
      // recording a silently incomplete assignment.
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.incomePlannerAssignmentNeedsAccount,
      );
      return;
    }
    final symbol = _symbolCtl.text.trim().toUpperCase();
    final optionSymbol = _optionSymbolCtl.text.trim();
    final credit = Decimal.parse(_creditCtl.text.trim());
    final debit = _debitCtl.text.trim().isEmpty
        ? null
        : Decimal.parse(_debitCtl.text.trim());
    final strike = _strikeCtl.text.trim().isEmpty
        ? null
        : Decimal.parse(_strikeCtl.text.trim());
    final contractSize = int.parse(_contractSizeCtl.text.trim());
    final contractQuantity = int.parse(_contractQuantityCtl.text.trim());
    final fees = Decimal.parse(_feesCtl.text.trim());
    setState(() => _busy = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(tradeJournalRepositoryProvider.future);
      final ledger = await ref.read(optionsJournalLedgerServiceProvider.future);
      final market = widget.prefilled?.contract.market.wire;
      final assetMarket =
          assetMarketFromWire(_loaded?.underlyingMarket ?? market) ??
          inferAssetMarket(symbol);
      final underlyingAssetId = Asset.idFor(assetMarket, symbol);
      TradeJournalEntry saved;
      final realized = (debit == null)
          ? null
          : (credit - debit) * Decimal.fromInt(contractQuantity) - fees;
      final closedAt = _status == TradeJournalStatus.open
          ? null
          : (_closedAt ?? DateTime.now().toUtc());
      if (_loaded != null) {
        saved = await repo.update(
          _loaded!.copyWith(
            underlyingAssetId: underlyingAssetId,
            strategy: _strategy,
            symbol: symbol,
            optionSymbol: optionSymbol,
            openedAt: _openedAt,
            expirationAt: _expirationAt,
            entryCredit: credit,
            exitDebit: debit,
            fees: fees,
            realizedPnl: realized,
            currency: _currency,
            status: _status,
            closedAt: closedAt,
            notes: _notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim(),
            brokerageAccountId: _brokerageAccountId,
            cashAccountId: _cashAccountId,
            underlyingMarket: _loaded!.underlyingMarket ?? market,
            strikePrice: strike,
            contractSize: contractSize,
            contractQuantity: contractQuantity,
          ),
        );
      } else {
        saved = await repo.create(
          underlyingAssetId: underlyingAssetId,
          strategy: _strategy,
          symbol: symbol,
          optionSymbol: optionSymbol,
          openedAt: _openedAt,
          expirationAt: _expirationAt,
          entryCredit: credit,
          currency: _currency,
          status: _status,
          closedAt: closedAt,
          exitDebit: debit,
          fees: fees,
          realizedPnl: realized,
          notes: _notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim(),
          brokerageAccountId: _brokerageAccountId,
          cashAccountId: _cashAccountId,
          underlyingMarket: market,
          strikePrice: strike,
          contractSize: contractSize,
          contractQuantity: contractQuantity,
        );
      }
      unawaited(
        ref
            .read(formDefaultsProvider.notifier)
            .rememberTrade(
              accountId: _brokerageAccountId,
              cashAccountId: _cashAccountId,
              currency: _currency,
            ),
      );
      await ledger.mirror(saved);
      widget.dirty.markPristine();
      if (mounted) unawaited(Navigator.of(context).maybePop());
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final existing = _loaded;
    if (existing == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.incomePlannerJournalDeleteTitle),
      body: Text(l10n.incomePlannerJournalDeleteBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(tradeJournalRepositoryProvider.future);
      final ledger = await ref.read(optionsJournalLedgerServiceProvider.future);
      await ledger.removeMirrors(existing.id);
      await repo.remove(existing);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonDeleteFailed);
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.existingId != null;
    final accountsAsync = ref.watch(accountsStreamProvider);
    return AppSheet(
      title: isEdit
          ? l10n.incomePlannerJournalEditTitle
          : l10n.incomePlannerJournalAddCta,
      footer: AppSheetFooter(
        submitLabel: l10n.incomePlannerSaveAction,
        cancelLabel: l10n.commonCancel,
        onSubmit: _save,
        busy: _busy,
      ),
      child: accountsAsync.whenOrLoading(
        context: context,
        error: (_, _) => _buildForm(l10n, const <Account>[]),
        data: (accounts) => _buildForm(l10n, accounts),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n, List<Account> accounts) {
    final brokerageAccounts = accounts
        .where((a) => a.type == AccountCategory.broker)
        .toList(growable: false);
    final cashAccounts = accounts
        .where(
          (a) =>
              a.type == AccountCategory.bank ||
              a.type == AccountCategory.cash ||
              a.type == AccountCategory.broker,
        )
        .toList(growable: false);
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabeledTextField(
            label: l10n.incomePlannerSymbolLabel,
            hint: l10n.incomePlannerSymbolHint,
            controller: _symbolCtl,
            validator: (value) => _requiredText(value, l10n),
          ),
          const SizedBox(height: AppSpacing.s12),
          _LabeledTextField(
            label: l10n.incomePlannerJournalOptionSymbolLabel,
            hint: l10n.incomePlannerJournalOptionSymbolHint,
            controller: _optionSymbolCtl,
            validator: (value) => _requiredText(value, l10n),
          ),
          const SizedBox(height: AppSpacing.s12),
          _StrategySelect(
            value: _strategy,
            onChanged: (v) {
              widget.dirty.markDirty();
              setState(() => _strategy = v);
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          DateField(
            label: l10n.incomePlannerJournalOpenedAtLabel,
            initialValue: _openedAt,
            required: true,
            onChanged: (value) {
              if (value != null) {
                widget.dirty.markDirty();
                setState(() => _openedAt = value.toUtc());
              }
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          DateField(
            label: l10n.incomePlannerJournalExpirationLabel,
            initialValue: _expirationAt,
            required: true,
            firstDate: _openedAt,
            onChanged: (value) {
              widget.dirty.markDirty();
              setState(() => _expirationAt = value?.toUtc());
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          if (accounts.isNotEmpty) ...[
            AccountPicker(
              label: l10n.incomePlannerJournalBrokerageAccountLabel,
              accounts: brokerageAccounts.isEmpty
                  ? accounts
                  : brokerageAccounts,
              value: _brokerageAccountId,
              onChanged: (v) {
                widget.dirty.markDirty();
                setState(() => _brokerageAccountId = v);
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            AccountPicker(
              label: l10n.incomePlannerJournalCashAccountLabel,
              accounts: cashAccounts.isEmpty ? accounts : cashAccounts,
              value: _cashAccountId,
              onChanged: (v) {
                widget.dirty.markDirty();
                setState(() => _cashAccountId = v);
              },
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          CurrencyPicker(
            value: _currency,
            label: l10n.formCurrencyPickerLabelDefault,
            onChanged: (value) {
              if (value != null) {
                widget.dirty.markDirty();
                setState(() => _currency = value);
              }
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          _LabeledTextField(
            label: l10n.incomePlannerJournalCreditLabel,
            hint: l10n.incomePlannerJournalAmountHint,
            controller: _creditCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) => _validateDecimal(
              value,
              l10n: l10n,
              required: true,
              allowZero: true,
            ),
          ),
          _TotalPremiumPreview(
            creditController: _creditCtl,
            sizeController: _contractSizeCtl,
            quantityController: _contractQuantityCtl,
            currency: _currency,
          ),
          const SizedBox(height: AppSpacing.s12),
          _LabeledTextField(
            label: l10n.incomePlannerJournalDebitLabel,
            hint: l10n.incomePlannerJournalAmountHint,
            controller: _debitCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) => _validateDecimal(
              value,
              l10n: l10n,
              required: _status == TradeJournalStatus.closed,
              allowZero: true,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _LabeledTextField(
            label: l10n.incomePlannerJournalStrikeLabel,
            hint: l10n.incomePlannerJournalAmountHint,
            controller: _strikeCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) => _validateDecimal(
              value,
              l10n: l10n,
              required: _status == TradeJournalStatus.assigned,
              allowZero: false,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _LabeledTextField(
            label: l10n.incomePlannerJournalContractSizeLabel,
            hint: '100',
            controller: _contractSizeCtl,
            keyboardType: TextInputType.number,
            validator: (value) => _validatePositiveInt(value, l10n),
          ),
          const SizedBox(height: AppSpacing.s12),
          _LabeledTextField(
            label: l10n.incomePlannerJournalContractQuantityLabel,
            hint: '1',
            controller: _contractQuantityCtl,
            keyboardType: TextInputType.number,
            validator: (value) => _validatePositiveInt(value, l10n),
          ),
          const SizedBox(height: AppSpacing.s12),
          _LabeledTextField(
            label: l10n.incomePlannerJournalFeesLabel,
            hint: '0.00',
            controller: _feesCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) => _validateDecimal(
              value,
              l10n: l10n,
              required: true,
              allowZero: true,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _StatusSelect(
            value: _status,
            onChanged: (v) {
              widget.dirty.markDirty();
              setState(() {
                _status = v;
                _closedAt = v == TradeJournalStatus.open
                    ? null
                    : (_closedAt ?? DateTime.now().toUtc());
              });
            },
          ),
          AnimatedSizeFade(
            visible: _status != TradeJournalStatus.open,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s12),
              child: DateField(
                label: l10n.incomePlannerJournalClosedAtLabel,
                initialValue: _closedAt,
                required: _status != TradeJournalStatus.open,
                firstDate: _openedAt,
                onChanged: (value) {
                  widget.dirty.markDirty();
                  setState(() => _closedAt = value?.toUtc());
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _LabeledTextField(
            label: l10n.incomePlannerJournalNotesLabel,
            hint: '',
            controller: _notesCtl,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.s12),
          if (_loaded != null) ...[
            FButton(
              variant: FButtonVariant.destructive,
              onPress: _busy ? null : _delete,
              child: Text(l10n.commonDelete),
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
        ],
      ),
    );
  }

  void _hydrateAccountDefaults(List<Account> accounts) {
    if (_hydratedAccounts || accounts.isEmpty) return;
    final brokerAccounts = accounts
        .where((a) => a.type == AccountCategory.broker)
        .toList(growable: false);
    final cashAccounts = accounts
        .where(
          (a) =>
              a.type == AccountCategory.bank ||
              a.type == AccountCategory.cash ||
              a.type == AccountCategory.broker,
        )
        .toList(growable: false);
    if (_brokerageAccountId == null ||
        !accounts.any((a) => a.id == _brokerageAccountId)) {
      _brokerageAccountId = brokerAccounts.isEmpty
          ? accounts.first.id
          : brokerAccounts.first.id;
    }
    if (_cashAccountId == null ||
        !accounts.any((a) => a.id == _cashAccountId)) {
      _cashAccountId = cashAccounts.isEmpty
          ? _brokerageAccountId
          : cashAccounts.first.id;
    }
    _hydratedAccounts = true;
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.captionLabelStyle.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        FTextFormField(
          control: FTextFieldControl.managed(controller: controller),
          hint: hint,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
        ),
      ],
    );
  }
}

String? _requiredText(String? value, AppLocalizations l10n) {
  if ((value ?? '').trim().isEmpty) return l10n.commonRequiredField;
  return null;
}

String? _validateDecimal(
  String? value, {
  required AppLocalizations l10n,
  required bool required,
  required bool allowZero,
}) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return required ? l10n.formAmountFieldInvalid : null;
  final parsed = Decimal.tryParse(raw);
  if (parsed == null ||
      parsed < Decimal.zero ||
      (!allowZero && parsed == Decimal.zero)) {
    return l10n.formAmountFieldInvalid;
  }
  return null;
}

String? _validatePositiveInt(String? value, AppLocalizations l10n) {
  final parsed = int.tryParse((value ?? '').trim());
  if (parsed == null || parsed <= 0) {
    return l10n.incomePlannerPositiveNumberValidation;
  }
  return null;
}

/// Live "credit × contract size × quantity" preview so a per-contract
/// price can never be mistaken for the total premium (the classic 100×
/// data-entry error).
class _TotalPremiumPreview extends ConsumerWidget {
  const _TotalPremiumPreview({
    required this.creditController,
    required this.sizeController,
    required this.quantityController,
    required this.currency,
  });

  final TextEditingController creditController;
  final TextEditingController sizeController;
  final TextEditingController quantityController;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    return ListenableBuilder(
      listenable: Listenable.merge([
        creditController,
        sizeController,
        quantityController,
      ]),
      builder: (context, _) {
        final credit = Decimal.tryParse(creditController.text.trim());
        final size = int.tryParse(sizeController.text.trim());
        final quantity = int.tryParse(quantityController.text.trim());
        if (credit == null || size == null || quantity == null) {
          return const SizedBox.shrink();
        }
        final total =
            credit * Decimal.fromInt(size) * Decimal.fromInt(quantity);
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s4),
          child: Text(
            l10n.incomePlannerJournalTotalCredit(
              formatters.currency(total, code: currency),
            ),
            style: context.captionStyle,
          ),
        );
      },
    );
  }
}

class _StrategySelect extends StatelessWidget {
  const _StrategySelect({required this.value, required this.onChanged});

  final OptionsStrategyKind value;
  final ValueChanged<OptionsStrategyKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedRow<OptionsStrategyKind>(
      options: OptionsStrategyKind.values,
      value: value,
      labelOf: (o) => optionsStrategyKindShortLabel(l10n, o),
      onChanged: onChanged,
    );
  }
}

class _StatusSelect extends StatelessWidget {
  const _StatusSelect({required this.value, required this.onChanged});

  final TradeJournalStatus value;
  final ValueChanged<TradeJournalStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedRow<TradeJournalStatus>(
      options: TradeJournalStatus.values,
      value: value,
      labelOf: (o) => tradeJournalStatusLabel(l10n, o),
      onChanged: onChanged,
    );
  }
}
