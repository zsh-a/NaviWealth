import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/providers.dart';
import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import '../data/providers.dart';
import '../domain/models/lot.dart';
import '../domain/trade_entry/trade_draft.dart' show TradeDraft, TradeType;
import '../domain/trade_entry/trade_entry_errors.dart';
import '../domain/trade_entry/trade_entry_prefill.dart';

/// Create / edit form for a security trade (stock / ETF / crypto).
///
/// Asset lookup is fully local (FIR-77): the picker reads from the seed
/// catalog + owned securities and never makes a network call. Selecting a
/// catalog row that the user has never traded triggers an `upsertSecurity`
/// at submit-time so the resulting postings always point at a real
/// `assets` row, satisfying the FIR-75 foreign-key contract.
class TradeEntryFormPage extends ConsumerStatefulWidget {
  const TradeEntryFormPage({
    super.key,
    this.assetId,
    this.accountId,
    this.prefill,
  });

  /// Pre-selected asset id. When null the user picks via [SymbolField].
  final String? assetId;

  /// Pre-selected account id.
  final String? accountId;

  /// Optional values supplied by an upstream workflow, such as rebalance.
  final TradeEntryPrefill? prefill;

  @override
  ConsumerState<TradeEntryFormPage> createState() => _TradeEntryFormPageState();
}

class _TradeEntryFormPageState extends ConsumerState<TradeEntryFormPage>
    with
        OptimisticFormSubmit<TradeEntryFormPage>,
        FormDirtyGuard<TradeEntryFormPage> {
  @override
  String get leaveFallback => AppRoutes.activity;

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

  TradeType _type = TradeType.buy;
  String? _accountId;
  String? _cashAccountId;
  String? _currency = 'CNY';
  DateTime _tradeDate = DateTime.now();
  LocalSecurityChoice? _selected;
  bool _busy = false;
  bool _hydratedDefaults = false;

  // transferIn / transferOut are deliberately absent from this form —
  // they can never be created as a single user-entered leg.
  // `TransferFormPage` (under `/activity/accounts/transfer`) writes the two
  // legs atomically via `JournalEntryRepository`.
  static const _tradeTypes = [
    TradeType.buy,
    TradeType.sell,
    TradeType.valuationAdjust,
  ];

  String _typeLabel(AppLocalizations l10n, TradeType type) {
    return switch (type) {
      TradeType.buy => l10n.tradeTypeBuy,
      TradeType.sell => l10n.tradeTypeSell,
      TradeType.valuationAdjust => l10n.tradeTypeValuationAdjust,
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
    final prefill = widget.prefill;
    if (prefill != null) {
      _type = prefill.type;
      _currency = prefill.currency;
      _tradeDate = prefill.tradeDate ?? _tradeDate;
      _quantityController.text = prefill.quantity.toString();
      _priceController.text = prefill.price?.toString() ?? '';
      _feeController.text = prefill.fee?.toString() ?? '0';
      _taxController.text = prefill.tax?.toString() ?? '0';
      _noteController.text = prefill.note ?? '';
    }
    // `_feeController`/`_taxController` carry a "0" seed — bind here so
    // that default is the baseline, not a user edit.
    dirty.bindTextControllers([
      _quantityController,
      _priceController,
      _feeController,
      _taxController,
      _noteController,
    ]);
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
    final securitiesRepo = await ref.read(
      securitiesAssetRepositoryProvider.future,
    );
    final tradeService = await ref.read(tradeEntryServiceProvider.future);
    final jeRepo = await ref.read(journalEntryRepositoryProvider.future);
    final priceRepo = await ref.read(priceRepositoryProvider.future);
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
      ref
          .read(formDefaultsProvider.notifier)
          .rememberTrade(
            accountId: accountId,
            cashAccountId: _cashAccountId,
            currency: currency,
          ),
    );

    // For buys with a known price, check whether the cash account would
    // go negative and prompt the user to confirm.
    if (type == TradeType.buy && price != null) {
      final cashOut =
          quantity * price + (fee ?? Decimal.zero) + (tax ?? Decimal.zero);
      final cashAccountId = _cashAccountId ?? accountId;
      final currentBalance = await jeRepo.balanceByAccountUnit(
        cashAccountId,
        currency,
      );
      if (!mounted) return;
      final resulting = currentBalance - cashOut;
      if (resulting < Decimal.zero) {
        final resultingLabel = context
            .formatters(ref)
            .currency(resulting, code: currency);
        final confirmed = await showConfirmDialog(
          context: context,
          title: Text(l10n.tradeEntryCashOverdrawTitle),
          body: Text(l10n.tradeEntryCashOverdrawMessage(resultingLabel)),
          cancelLabel: l10n.commonCancel,
          confirmLabel: l10n.tradeEntryCashOverdrawProceed,
        );
        if (confirmed != true) {
          setState(() => _busy = false);
          return;
        }
      }
    }

    // The record is being persisted — the post-save pop must not prompt.
    dirty.markPristine();
    await submitOptimistic(
      // Use the underlying Navigator (rather than `context.pop()`) so the
      // form is portable to test surfaces that mount it without a router.
      // GoRouter sub-routes sit on the same Navigator stack, so this is
      // a no-op difference in production.
      pop: () {
        Haptics.success();
        Navigator.of(context).pop(true);
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
        final plan = await tradeService.buildPlan(draft, openLots: <Lot>[]);
        final tx = plan.trade;
        final uid = await currentUserId();

        if (type == TradeType.buy || type == TradeType.sell) {
          final cashAcct = _cashAccountId ?? accountId;
          final feeAccountId = AccountRepository.systemAccountIdForPath(
            'expense:trading:fee',
            ownerUserId: uid,
          );
          final taxAccountId = AccountRepository.systemAccountIdForPath(
            'expense:trading:tax',
            ownerUserId: uid,
          );

          if (type == TradeType.buy) {
            final build = JournalEntryBuilders.buy(
              date: tx.tradeDate,
              accountId: accountId,
              cashAccountId: cashAcct,
              assetUnit: tx.assetId,
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
            await jeRepo.create(entry: build.entry, postings: build.postings);
            await priceRepo.record(
              unit: tx.assetId,
              quoteCurrency: currency,
              observedOn: tx.tradeDate,
              perUnit: tx.price,
              source: 'trade',
            );
          } else {
            // Sell — cost basis comes from the resolved lots.
            final capGainsAccountId = AccountRepository.systemAccountIdForPath(
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
                  ? (first.costBasis / first.quantity).toDecimal(
                      scaleOnInfinitePrecision: 16,
                    )
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
              assetUnit: tx.assetId,
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
            await jeRepo.create(entry: build.entry, postings: build.postings);
            await priceRepo.record(
              unit: tx.assetId,
              quoteCurrency: currency,
              observedOn: tx.tradeDate,
              perUnit: tx.price,
              source: 'trade',
            );
          }
        } else {
          final equityAccountId = AccountRepository.systemAccountIdForPath(
            'equity:adjustments',
            ownerUserId: uid,
          );
          final build = JournalEntryBuilders.valuationAdjust(
            date: tx.tradeDate,
            accountId: accountId,
            equityAccountId: equityAccountId,
            assetUnit: tx.assetId,
            quantity: tx.quantity,
            newValuation: tx.price,
            currency: currency,
            narration: note,
          );
          await jeRepo.create(entry: build.entry, postings: build.postings);
          await priceRepo.record(
            unit: tx.assetId,
            quoteCurrency: currency,
            observedOn: tx.tradeDate,
            perUnit: tx.price,
            source: 'manual',
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);

    return guardedScope(
      child: FScaffold(
        header: FHeader.nested(
          title: Text(l10n.tradeEntryAppBarTitle),
          prefixes: [backHeaderAction(context, confirmLeave: handleBackIntent)],
        ),
        childPad: false,
        resizeToAvoidBottomInset: false,
        child: Material(
          color: Colors.transparent,
          child: accountsAsync.when(
            loading: () => const Center(child: FCircularProgress()),
            error: (e, _) => Center(child: Text(l10n.commonLoadError('$e'))),
            data: (accounts) => _buildForm(accounts),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(List<Account> accounts) {
    final l10n = AppLocalizations.of(context);
    final eligible = accounts
        .where(
          (a) =>
              a.type == AccountCategory.broker ||
              a.type == AccountCategory.crypto,
        )
        .toList(growable: false);

    // Fall back to the first eligible account once we know the workspace
    // contents. Only fires once per page mount so the user can deliberately
    // clear the picker without us re-imposing a default.
    if (!_hydratedDefaults) {
      final pool = eligible.isEmpty ? accounts : eligible;
      if (_accountId == null && pool.isNotEmpty) {
        _accountId = pool.first.id;
      } else if (_accountId != null && !pool.any((a) => a.id == _accountId)) {
        _accountId = pool.isEmpty ? null : pool.first.id;
      }
      _hydratedDefaults = true;
    }

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: AppFormScaffoldBody(
        action: SizedBox(
          width: double.infinity,
          child: FButton(
            key: const Key('trade-entry-submit'),
            variant: FButtonVariant.primary,
            onPress: _busy ? null : _submit,
            child: Text(_busy ? l10n.commonSaving : l10n.commonSave),
          ),
        ),
        children: [
          _buildAssetSearch(),
          const SizedBox(height: 12),

          _buildTypeSelector(),
          const SizedBox(height: 12),

          AccountPicker(
            accounts: eligible.isEmpty ? accounts : eligible,
            value: _accountId,
            onChanged: (v) => setState(() {
              _accountId = v;
              dirty.markDirty();
            }),
          ),
          if (_type == TradeType.buy || _type == TradeType.sell) ...[
            const SizedBox(height: 12),
            AccountPicker(
              key: const Key('trade-entry-cash-account'),
              label: l10n.tradeEntryCashAccountLabel,
              accounts: accounts
                  .where(
                    (a) =>
                        a.type == AccountCategory.bank ||
                        a.type == AccountCategory.cash,
                  )
                  .toList(growable: false),
              value: _cashAccountId,
              onChanged: (v) => setState(() {
                _cashAccountId = v;
                dirty.markDirty();
              }),
            ),
          ],
          const SizedBox(height: 12),

          AmountField(
            key: const Key('trade-entry-quantity'),
            label: l10n.tradeEntryQuantityLabel,
            controller: _quantityController,
            focusNode: _quantityFocus,
            onFieldSubmitted: (_) => _priceFocus.requestFocus(),
            helperText: _decimalScaleHint(l10n),
          ),
          const SizedBox(height: 12),

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
          const SizedBox(height: 12),

          DateField(
            label: l10n.tradeEntryDateLabel,
            initialValue: _tradeDate,
            required: true,
            onChanged: (d) {
              if (d != null) {
                setState(() {
                  _tradeDate = d;
                  dirty.markDirty();
                });
              }
            },
          ),
          const SizedBox(height: 12),

          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() {
              _currency = v;
              dirty.markDirty();
            }),
          ),
          const SizedBox(height: 12),

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
              const SizedBox(width: 12),
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
          const SizedBox(height: 12),

          NoteField(controller: _noteController, focusNode: _noteFocus),
        ],
      ),
    );
  }

  Widget _buildAssetSearch() {
    return SymbolField(
      onChanged: (choice) {
        setState(() {
          _selected = choice;
          dirty.markDirty();
          if (choice != null) {
            _currency = choice.currency;
            // Hand focus to the first amount field as soon as an asset
            // is picked so the user can keep typing without reaching
            // back up the form.
            _quantityFocus.requestFocus();
          }
        });
      },
    );
  }

  Widget _buildTypeSelector() {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in _tradeTypes)
          FButton(
            variant: (_type == t)
                ? FButtonVariant.primary
                : FButtonVariant.outline,
            onPress: () => setState(() {
              _type = t;
              dirty.markDirty();
            }),
            child: Text(_typeLabel(l10n, t)),
          ),
      ],
    );
  }

  String _decimalScaleHint(AppLocalizations l10n) {
    if (_selected == null) return l10n.tradeEntryDecimalScaleHintGeneric;
    return l10n.tradeEntryDecimalScaleHint(_decimalScale(_selected!.type));
  }
}

Decimal? _nonZeroOr(Decimal? v) => v == null || v == Decimal.zero ? null : v;
