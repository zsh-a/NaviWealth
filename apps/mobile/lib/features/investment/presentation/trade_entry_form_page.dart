import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics/haptics.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/repositories/providers.dart';
import '../../../data/securities_catalog/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import '../data/providers.dart';
import '../domain/models/lot.dart';
import '../domain/trade_entry/trade_draft.dart';
import '../domain/trade_entry/trade_entry_errors.dart';

/// Create / edit form for a security trade (stock / ETF / crypto).
///
/// Asset lookup is fully local (FIR-77): the picker reads from the seed
/// catalog + owned securities and never makes a network call. Selecting a
/// catalog row that the user has never traded triggers an `upsertSecurity`
/// at submit-time so the resulting `transactions.assetId` always points
/// at a real `assets` row, satisfying the FIR-75 foreign-key contract.
class TradeEntryFormPage extends ConsumerStatefulWidget {
  const TradeEntryFormPage({super.key, this.assetId, this.accountId});

  /// Pre-selected asset id. When null the user picks via [LocalSecuritiesPicker].
  final String? assetId;

  /// Pre-selected account id.
  final String? accountId;

  @override
  ConsumerState<TradeEntryFormPage> createState() => _TradeEntryFormPageState();
}

class _TradeEntryFormPageState extends ConsumerState<TradeEntryFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _feeController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');
  final _noteController = TextEditingController();

  TransactionType _type = TransactionType.buy;
  String? _accountId;
  String? _currency = 'CNY';
  DateTime _tradeDate = DateTime.now();
  LocalSecurityChoice? _selected;
  bool _busy = false;

  static const _tradeTypes = [
    TransactionType.buy,
    TransactionType.sell,
    TransactionType.transferIn,
    TransactionType.transferOut,
    TransactionType.valuationAdjust,
  ];

  String _typeLabel(AppLocalizations l10n, TransactionType type) {
    return switch (type) {
      TransactionType.buy => l10n.tradeTypeBuy,
      TransactionType.sell => l10n.tradeTypeSell,
      TransactionType.transferIn => l10n.tradeTypeTransferIn,
      TransactionType.transferOut => l10n.tradeTypeTransferOut,
      TransactionType.valuationAdjust => l10n.tradeTypeValuationAdjust,
      _ => type.name,
    };
  }

  @override
  void initState() {
    super.initState();
    _accountId = widget.accountId;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _feeController.dispose();
    _taxController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  int _decimalScale(AssetType type) {
    switch (type) {
      case AssetType.crypto:
        return 18;
      case AssetType.stock:
      case AssetType.etf:
      case AssetType.mutualFund:
        return 8;
      default:
        return 8;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final selected = _selected;
    if (selected == null) return;

    setState(() => _busy = true);
    try {
      final securitiesRepo =
          await ref.read(securitiesAssetRepositoryProvider.future);
      // Persist the catalog row into `assets` (or hand-entered row, if it
      // came from the manual sheet). `upsertSecurity` is idempotent on
      // (market, symbol), so re-recording trades on the same instrument
      // does not bloat the outbox.
      final asset = await securitiesRepo.upsertSecurity(
        symbol: selected.symbol,
        market: selected.market,
        type: selected.type,
        currency: selected.currency,
        name: selected.name,
        isin: selected.isin,
      );

      final draft = TradeDraft(
        type: _type,
        asset: asset,
        accountId: _accountId!,
        quantity: Decimal.parse(_quantityController.text.trim()),
        price: _priceController.text.trim().isEmpty
            ? null
            : Decimal.parse(_priceController.text.trim()),
        currency: _currency!,
        tradeDate: _tradeDate,
        fee: Decimal.tryParse(_feeController.text.trim()),
        tax: Decimal.tryParse(_taxController.text.trim()),
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      final tradeService = await ref.read(tradeEntryServiceProvider.future);
      final plan = await tradeService.buildPlan(draft, openLots: <Lot>[]);

      final repo = await ref.read(transactionRepositoryProvider.future);
      await repo.recordTrade(plan);

      if (!mounted) return;
      Haptics.success();
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tradeEntrySuccess)),
      );
      context.pop();
    } on TradeEntryException catch (e) {
      if (!mounted) return;
      Haptics.error();
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tradeEntryFailure(e.message))),
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.error();
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tradeEntryFailure('$e'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tradeEntryAppBarTitle),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.commonLoadError('$e'))),
        data: (accounts) => _buildForm(accounts),
      ),
    );
  }

  Widget _buildForm(List<Account> accounts) {
    final l10n = AppLocalizations.of(context);
    final eligible = accounts
        .where((a) =>
            a.type == AccountType.brokerage ||
            a.type == AccountType.cryptoWallet)
        .toList(growable: false);

    return Form(
      key: _formKey,
      child: ListView(
        padding: Spacing.pageMobile,
        children: [
          _buildAssetSearch(),
          const SizedBox(height: Spacing.s12),

          _buildTypeSelector(),
          const SizedBox(height: Spacing.s12),

          AccountPicker(
            accounts: eligible.isEmpty ? accounts : eligible,
            value: _accountId,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: Spacing.s12),

          AmountField(
            key: const Key('trade-entry-quantity'),
            label: l10n.tradeEntryQuantityLabel,
            controller: _quantityController,
            helperText: _decimalScaleHint(l10n),
          ),
          const SizedBox(height: Spacing.s12),

          AmountField(
            key: const Key('trade-entry-price'),
            label: l10n.tradeEntryPriceLabel,
            controller: _priceController,
            currencyCode: _currency,
            required: false,
            helperText: l10n.tradeEntryPriceHelper,
          ),
          const SizedBox(height: Spacing.s12),

          DateField(
            label: l10n.tradeEntryDateLabel,
            initialValue: _tradeDate,
            required: true,
            onChanged: (d) {
              if (d != null) setState(() => _tradeDate = d);
            },
          ),
          const SizedBox(height: Spacing.s12),

          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() => _currency = v),
          ),
          const SizedBox(height: Spacing.s12),

          Row(
            children: [
              Expanded(
                child: AmountField(
                  label: l10n.tradeEntryFeeLabel,
                  controller: _feeController,
                  currencyCode: _currency,
                  required: false,
                ),
              ),
              const SizedBox(width: Spacing.s12),
              Expanded(
                child: AmountField(
                  label: l10n.tradeEntryTaxLabel,
                  controller: _taxController,
                  currencyCode: _currency,
                  required: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.s12),

          NoteField(controller: _noteController),
          const SizedBox(height: Spacing.s24),

          FilledButton(
            key: const Key('trade-entry-submit'),
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? l10n.commonSaving : l10n.commonSave),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetSearch() {
    final l10n = AppLocalizations.of(context);
    final searchAsync = ref.watch(securitiesSearchServiceProvider);
    return searchAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text(l10n.tradeEntryCatalogLoadError('$e')),
      data: (search) => LocalSecuritiesPicker(
        search: search,
        onSelected: (choice) {
          setState(() {
            _selected = choice;
            if (choice != null) {
              _currency = choice.currency;
            }
          });
        },
      ),
    );
  }

  Widget _buildTypeSelector() {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in _tradeTypes)
          AppChoiceChip(
            label: Text(_typeLabel(l10n, t)),
            selected: _type == t,
            onSelected: (s) {
              if (s) setState(() => _type = t);
            },
          ),
      ],
    );
  }

  String _decimalScaleHint(AppLocalizations l10n) {
    if (_selected == null) return l10n.tradeEntryDecimalScaleHintGeneric;
    return l10n.tradeEntryDecimalScaleHint(_decimalScale(_selected!.type));
  }
}
