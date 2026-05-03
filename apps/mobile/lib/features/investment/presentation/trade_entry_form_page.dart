import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/haptics.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/repositories/account_repository.dart';
import '../../../data/repositories/journal_entry_builders.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/mutation_context.dart';
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

class _TradeEntryFormPageState extends ConsumerState<TradeEntryFormPage>
    with OptimisticFormSubmit<TradeEntryFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _feeController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');
  final _noteController = TextEditingController();

  // Focus chain: quantity → price → fee → tax → note. Submit fires from
  // the last `done` action so the user can complete an entry without
  // ever lifting their thumb to tap fields. The wrap into a list keeps
  // dispose tidy.
  final _quantityFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _feeFocus = FocusNode();
  final _taxFocus = FocusNode();
  final _noteFocus = FocusNode();

  TransactionType _type = TransactionType.buy;
  String? _accountId;
  String? _cashAccountId;
  String? _currency = 'CNY';
  DateTime _tradeDate = DateTime.now();
  LocalSecurityChoice? _selected;
  bool _busy = false;
  bool _hydratedDefaults = false;

  // FIR-124: transferIn / transferOut are deliberately absent from this
  // form — they can never be created as a single user-entered leg.
  // FIR-131 wave 3a wired up `TransferFormPage` (under `/accounts/transfer`)
  // which writes the two legs atomically via `JournalEntryRepository`,
  // and that's now the only path to transfer creation.
  static const _tradeTypes = [
    TransactionType.buy,
    TransactionType.sell,
    TransactionType.valuationAdjust,
  ];

  String _typeLabel(AppLocalizations l10n, TransactionType type) {
    return switch (type) {
      TransactionType.buy => l10n.tradeTypeBuy,
      TransactionType.sell => l10n.tradeTypeSell,
      TransactionType.valuationAdjust => l10n.tradeTypeValuationAdjust,
      _ => type.name,
    };
  }

  @override
  void initState() {
    super.initState();
    // Constructor-supplied pre-selection wins over the persisted default.
    _accountId = widget.accountId;
    final defaults = ref.read(formDefaultsProvider);
    _accountId ??= defaults.tradeAccountId;
    _cashAccountId = defaults.tradeCashAccountId;
    if (defaults.tradeCurrency != null && defaults.tradeCurrency!.isNotEmpty) {
      _currency = defaults.tradeCurrency;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _feeController.dispose();
    _taxController.dispose();
    _noteController.dispose();
    _quantityFocus.dispose();
    _priceFocus.dispose();
    _feeFocus.dispose();
    _taxFocus.dispose();
    _noteFocus.dispose();
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
    final l10n = AppLocalizations.of(context);
    final securitiesRepo =
        await ref.read(securitiesAssetRepositoryProvider.future);
    final tradeService = await ref.read(tradeEntryServiceProvider.future);
    final repo = await ref.read(transactionRepositoryProvider.future);
    final jeRepo = await ref.read(journalEntryRepositoryProvider.future);
    final currentUserId = ref.read(currentUserIdProvider);
    if (!mounted) return;

    final type = _type;
    final accountId = _accountId!;
    final currency = _currency!;
    final tradeDate = _tradeDate;
    final quantity = Decimal.parse(_quantityController.text.trim());
    final price = _priceController.text.trim().isEmpty
        ? null
        : Decimal.parse(_priceController.text.trim());
    // Normalise zero to null so the JE builder's _normalizeOptionalAmount
    // doesn't reject a user-entered "0" as an invalid positive amount.
    final fee = _nonZeroOr(Decimal.tryParse(_feeController.text.trim()));
    final tax = _nonZeroOr(Decimal.tryParse(_taxController.text.trim()));
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    // Record this entry's account / currency as the next default.
    // Failure is silent — saving defaults is a UX nicety, not part of
    // the trade-recording success contract.
    unawaited(
      ref.read(formDefaultsProvider.notifier).rememberTrade(
            accountId: accountId,
            cashAccountId: _cashAccountId,
            currency: currency,
          ),
    );

    await submitOptimistic(
      // Use the underlying Navigator (rather than `context.pop()`) so the
      // form is portable to test surfaces that mount it without a router.
      // GoRouter sub-routes sit on the same Navigator stack, so this is
      // a no-op difference in production.
      pop: () {
        Haptics.success();
        Navigator.of(context).pop();
      },
      tag: 'trade-entry',
      // `TradeEntryException` carries a user-facing message; pass it
      // through so the snackbar reads "Couldn't record trade: <reason>"
      // instead of a generic "save failed".
      failureMessage: (error) => l10n.tradeEntryFailure(
        error is TradeEntryException ? error.message : '$error',
      ),
      retryLabel: l10n.commonRetry,
      write: () async {
        // Persist the catalog row into `assets` (or hand-entered row,
        // if it came from the manual sheet). `upsertSecurity` is
        // idempotent on (market, symbol), so re-recording trades on
        // the same instrument does not bloat the outbox.
        final asset = await securitiesRepo.upsertSecurity(
          symbol: selected.symbol,
          market: selected.market,
          type: selected.type,
          currency: selected.currency,
          name: selected.name,
          isin: selected.isin,
        );
        final draft = TradeDraft(
          type: type,
          asset: asset,
          accountId: accountId,
          quantity: quantity,
          price: price,
          currency: currency,
          tradeDate: tradeDate,
          fee: fee,
          tax: tax,
          note: note,
        );
        final plan =
            await tradeService.buildPlan(draft, openLots: <Lot>[]);
        final tx = plan.transaction;
        final uid = await currentUserId();

        if (type == TransactionType.buy || type == TransactionType.sell) {
          final cashAcct = _cashAccountId ?? accountId;
          final feeAccountId = AccountRepository.systemAccountIdForPath(
            'expense:trading:fee',
            ownerUserId: uid,
          );
          final taxAccountId = AccountRepository.systemAccountIdForPath(
            'expense:trading:tax',
            ownerUserId: uid,
          );

          if (type == TransactionType.buy) {
            final build = JournalEntryBuilders.buy(
              date: tx.tradeDate,
              accountId: accountId,
              cashAccountId: cashAcct,
              assetUnit: tx.assetId!,
              qty: tx.quantity,
              price: tx.price,
              quoteCurrency: currency,
              lotId: plan.createdLot?.id,
              acquiredOn: plan.createdLot?.openedAt,
              feeAmount: tx.fee,
              feeAccountId: tx.fee != null ? feeAccountId : null,
              feeCurrency: tx.fee != null ? currency : null,
              taxAmount: tx.tax,
              taxAccountId: tx.tax != null ? taxAccountId : null,
              taxCurrency: tx.tax != null ? currency : null,
              narration: note,
            );
            await jeRepo.create(
              entry: build.entry,
              postings: build.postings,
            );
          } else {
            // Sell — cost basis comes from the resolved lots.
            final capGainsAccountId =
                AccountRepository.systemAccountIdForPath(
              'income:capitalGains',
              ownerUserId: uid,
            );
            final pnl = plan.realizedPnL;
            Decimal costPerUnit;
            String costCurrency;
            String? sellLotId;
            DateTime? sellAcquiredOn;
            if (pnl.isNotEmpty) {
              final first = pnl.first;
              costPerUnit = first.quantity.sign != 0
                  ? (first.costBasis / first.quantity)
                      .toDecimal(scaleOnInfinitePrecision: 16)
                  : tx.price;
              costCurrency = first.currency;
              sellLotId = first.lotId;
              sellAcquiredOn = first.lotOpenedAt;
            } else {
              costPerUnit = tx.price;
              costCurrency = currency;
            }
            final build = JournalEntryBuilders.sell(
              date: tx.tradeDate,
              accountId: accountId,
              cashAccountId: cashAcct,
              capitalGainsAccountId: capGainsAccountId,
              assetUnit: tx.assetId!,
              qty: tx.quantity,
              price: tx.price,
              quoteCurrency: currency,
              costPerUnit: costPerUnit,
              costCurrency: costCurrency,
              lotId: sellLotId,
              acquiredOn: sellAcquiredOn,
              feeAmount: tx.fee,
              feeAccountId: tx.fee != null ? feeAccountId : null,
              feeCurrency: tx.fee != null ? currency : null,
              taxAmount: tx.tax,
              taxAccountId: tx.tax != null ? taxAccountId : null,
              taxCurrency: tx.tax != null ? currency : null,
              narration: note,
            );
            await jeRepo.create(
              entry: build.entry,
              postings: build.postings,
            );
          }
        } else {
          // valuationAdjust — no JE builder yet; use legacy path.
          await repo.recordTrade(plan);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);

    return Scaffold(
      appBar: GlassAppBar(
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

    // Fall back to the first eligible account once we know the workspace
    // contents. Only fires once per page mount so the user can deliberately
    // clear the picker without us re-imposing a default.
    if (!_hydratedDefaults) {
      final pool = eligible.isEmpty ? accounts : eligible;
      if (_accountId == null && pool.isNotEmpty) {
        _accountId = pool.first.id;
      } else if (_accountId != null &&
          !pool.any((a) => a.id == _accountId)) {
        _accountId = pool.isEmpty ? null : pool.first.id;
      }
      _hydratedDefaults = true;
    }

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: Spacing.pageMobile,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
          if (_type == TransactionType.buy ||
              _type == TransactionType.sell) ...[
            const SizedBox(height: Spacing.s12),
            AccountPicker(
              key: const Key('trade-entry-cash-account'),
              label: l10n.tradeEntryCashAccountLabel,
              accounts: accounts
                  .where((a) =>
                      a.type == AccountType.bank ||
                      a.type == AccountType.cash)
                  .toList(growable: false),
              value: _cashAccountId,
              onChanged: (v) => setState(() => _cashAccountId = v),
            ),
          ],
          const SizedBox(height: Spacing.s12),

          AmountField(
            key: const Key('trade-entry-quantity'),
            label: l10n.tradeEntryQuantityLabel,
            controller: _quantityController,
            focusNode: _quantityFocus,
            onFieldSubmitted: (_) => _priceFocus.requestFocus(),
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
            focusNode: _priceFocus,
            onFieldSubmitted: (_) => _feeFocus.requestFocus(),
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
                  focusNode: _feeFocus,
                  onFieldSubmitted: (_) => _taxFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: Spacing.s12),
              Expanded(
                child: AmountField(
                  label: l10n.tradeEntryTaxLabel,
                  controller: _taxController,
                  currencyCode: _currency,
                  required: false,
                  focusNode: _taxFocus,
                  onFieldSubmitted: (_) => _noteFocus.requestFocus(),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.s12),

          NoteField(controller: _noteController, focusNode: _noteFocus),
          const SizedBox(height: Spacing.s24),

          AppButton.primary(
            key: const Key('trade-entry-submit'),
            label: _busy ? l10n.commonSaving : l10n.commonSave,
            onPressed: _busy ? null : _submit,
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
              // Hand focus to the first amount field as soon as an asset
              // is picked so the user can keep typing without reaching
              // back up the form.
              _quantityFocus.requestFocus();
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

Decimal? _nonZeroOr(Decimal? v) =>
    v == null || v == Decimal.zero ? null : v;
