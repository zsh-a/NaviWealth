import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../finance/shared/forms/forms.dart';
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
  return showAppFormSheet(
    context: context,
    builder: (sheetCtx) =>
        _TradeJournalForm(existingId: existingId, prefilled: prefilled),
  );
}

class _TradeJournalForm extends ConsumerStatefulWidget {
  const _TradeJournalForm({this.existingId, this.prefilled});

  final String? existingId;
  final OptionsOpportunity? prefilled;

  @override
  ConsumerState<_TradeJournalForm> createState() => _TradeJournalFormState();
}

class _TradeJournalFormState extends ConsumerState<_TradeJournalForm> {
  late final TextEditingController _symbolCtl;
  late final TextEditingController _optionSymbolCtl;
  late final TextEditingController _creditCtl;
  late final TextEditingController _debitCtl;
  late final TextEditingController _strikeCtl;
  late final TextEditingController _contractSizeCtl;
  late final TextEditingController _notesCtl;

  OptionsStrategyKind _strategy = OptionsStrategyKind.cashSecuredPut;
  TradeJournalStatus _status = TradeJournalStatus.open;
  String _currency = 'USD';
  String? _brokerageAccountId;
  String? _cashAccountId;
  bool _hydratedAccounts = false;
  bool _busy = false;
  TradeJournalEntry? _loaded;

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
    _notesCtl = TextEditingController();
    if (pre != null) {
      _strategy = pre.strategy;
      _currency = pre.metrics.premium.currency;
    }
    final defaults = ref.read(formDefaultsProvider);
    _brokerageAccountId = defaults.tradeAccountId;
    _cashAccountId = defaults.tradeCashAccountId;
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
      _symbolCtl.text = entry.symbol;
      _optionSymbolCtl.text = entry.optionSymbol;
      _creditCtl.text = entry.entryCredit.toString();
      _debitCtl.text = entry.exitDebit?.toString() ?? '';
      _strikeCtl.text = entry.strikePrice?.toString() ?? '';
      _contractSizeCtl.text = (entry.contractSize ?? 100).toString();
      _notesCtl.text = entry.notes ?? '';
      _brokerageAccountId = entry.brokerageAccountId;
      _cashAccountId = entry.cashAccountId;
    });
  }

  @override
  void dispose() {
    _symbolCtl.dispose();
    _optionSymbolCtl.dispose();
    _creditCtl.dispose();
    _debitCtl.dispose();
    _strikeCtl.dispose();
    _contractSizeCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final symbol = _symbolCtl.text.trim().toUpperCase();
    final optionSymbol = _optionSymbolCtl.text.trim();
    if (symbol.isEmpty || optionSymbol.isEmpty) return;
    final credit = Decimal.tryParse(_creditCtl.text.trim());
    if (credit == null) return;
    final debit = _debitCtl.text.trim().isEmpty
        ? null
        : Decimal.tryParse(_debitCtl.text.trim());
    final strike = _strikeCtl.text.trim().isEmpty
        ? null
        : Decimal.tryParse(_strikeCtl.text.trim());
    final contractSize = int.tryParse(_contractSizeCtl.text.trim()) ?? 100;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(tradeJournalRepositoryProvider.future);
      final ledger = await ref.read(optionsJournalLedgerServiceProvider.future);
      final market = widget.prefilled?.contract.market.wire;
      TradeJournalEntry saved;
      if (_loaded != null) {
        final realized = (debit == null) ? null : credit - debit;
        final closedAt = _status == TradeJournalStatus.open
            ? null
            : DateTime.now().toUtc();
        saved = await repo.update(
          _loaded!.copyWith(
            strategy: _strategy,
            symbol: symbol,
            optionSymbol: optionSymbol,
            entryCredit: credit,
            exitDebit: debit,
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
          ),
        );
      } else {
        saved = await repo.create(
          strategy: _strategy,
          symbol: symbol,
          optionSymbol: optionSymbol,
          openedAt: DateTime.now().toUtc(),
          entryCredit: credit,
          currency: _currency,
          status: _status,
          notes: _notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim(),
          brokerageAccountId: _brokerageAccountId,
          cashAccountId: _cashAccountId,
          underlyingMarket: market,
          strikePrice: strike,
          contractSize: contractSize,
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
      if (mounted) unawaited(Navigator.of(context).maybePop());
    } finally {
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
        error: (_, _) => _buildForm(l10n, const <Account>[]),
        data: (accounts) => _buildForm(l10n, accounts),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n, List<Account> accounts) {
    _hydrateAccountDefaults(accounts);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LabeledTextField(
          label: l10n.incomePlannerSymbolLabel,
          hint: l10n.incomePlannerSymbolHint,
          controller: _symbolCtl,
        ),
        const SizedBox(height: AppSpacing.s12),
        _LabeledTextField(
          label: l10n.incomePlannerJournalOptionSymbolLabel,
          hint: l10n.incomePlannerJournalOptionSymbolHint,
          controller: _optionSymbolCtl,
        ),
        const SizedBox(height: AppSpacing.s12),
        _StrategySelect(
          value: _strategy,
          onChanged: (v) => setState(() => _strategy = v),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (accounts.isNotEmpty) ...[
          AccountPicker(
            label: l10n.incomePlannerJournalBrokerageAccountLabel,
            accounts: brokerageAccounts.isEmpty ? accounts : brokerageAccounts,
            value: _brokerageAccountId,
            onChanged: (v) => setState(() => _brokerageAccountId = v),
          ),
          const SizedBox(height: AppSpacing.s12),
          AccountPicker(
            label: l10n.incomePlannerJournalCashAccountLabel,
            accounts: cashAccounts.isEmpty ? accounts : cashAccounts,
            value: _cashAccountId,
            onChanged: (v) => setState(() => _cashAccountId = v),
          ),
          const SizedBox(height: AppSpacing.s12),
        ],
        _LabeledTextField(
          label: l10n.incomePlannerJournalCreditLabel,
          hint: l10n.incomePlannerJournalAmountHint,
          controller: _creditCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: AppSpacing.s12),
        _LabeledTextField(
          label: l10n.incomePlannerJournalDebitLabel,
          hint: l10n.incomePlannerJournalAmountHint,
          controller: _debitCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: AppSpacing.s12),
        _LabeledTextField(
          label: l10n.incomePlannerJournalStrikeLabel,
          hint: l10n.incomePlannerJournalAmountHint,
          controller: _strikeCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: AppSpacing.s12),
        _LabeledTextField(
          label: l10n.incomePlannerJournalContractSizeLabel,
          hint: '100',
          controller: _contractSizeCtl,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpacing.s12),
        _StatusSelect(
          value: _status,
          onChanged: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: AppSpacing.s12),
        _LabeledTextField(
          label: l10n.incomePlannerJournalNotesLabel,
          hint: '',
          controller: _notesCtl,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.s12),
      ],
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
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;

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
        FTextField(
          control: FTextFieldControl.managed(controller: controller),
          hint: hint,
          keyboardType: keyboardType,
          maxLines: maxLines,
        ),
      ],
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
