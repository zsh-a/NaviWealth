import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/haptics/haptics.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/shared/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../application/trade_entry_submission_service.dart';
import '../data/providers.dart';
import '../domain/trade_entry/trade_draft.dart' show TradeType;
import '../domain/trade_entry/trade_entry_errors.dart';
import '../domain/trade_entry/trade_entry_prefill.dart';

/// Create / edit form for a security trade (stock / ETF / crypto).
///
/// Asset lookup is fully local: the picker reads from the seed
/// catalog + owned securities and never makes a network call. Selecting a
/// catalog row that the user has never traded triggers an `upsertSecurity`
/// at submit-time so the resulting postings always point at a real
/// `assets` row, satisfying the foreign-key contract.
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
  String get leaveFallback => FinanceRoutes.activity;

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
    final l10n = AppLocalizations.of(context);
    final selected = _selected;
    if (selected == null) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.localSecuritiesValidationRequired,
      );
      return;
    }
    final accountId = _accountId;
    final currency = _currency;
    if (accountId == null || currency == null) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.formAccountPickerRequired,
      );
      return;
    }
    final quantity = Decimal.tryParse(_quantityController.text.trim());
    final priceText = _priceController.text.trim();
    final price = priceText.isEmpty ? null : Decimal.tryParse(priceText);
    if (quantity == null || (priceText.isNotEmpty && price == null)) {
      AppMessenger.show(context, ToastKind.error, l10n.formAmountFieldInvalid);
      return;
    }

    setState(() => _busy = true);
    final submissionService = await ref.read(
      tradeEntrySubmissionServiceProvider.future,
    );
    if (!mounted) return;

    final type = _type;
    final tradeDate = _tradeDate;
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
      final currentBalance = await submissionService.balanceByAccountUnit(
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
        await submissionService.submit(
          TradeEntrySubmissionRequest(
            symbol: selected.symbol,
            market: selected.market,
            assetType: selected.type,
            assetCurrency: selected.currency,
            assetName: selected.name,
            isin: selected.isin,
            type: type,
            accountId: accountId,
            cashAccountId: _cashAccountId,
            quantity: quantity,
            price: price,
            currency: currency,
            tradeDate: tradeDate,
            fee: fee,
            tax: tax,
            note: note,
            defaultNarration: (asset) =>
                _tradeNarration(type, quantity, asset, l10n),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);

    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(l10n.tradeEntryAppBarTitle),
        confirmLeave: handleBackIntent,
        child: accountsAsync.whenOrLoading(
          error: (e, _) => AppEmptyState.error(
            title: l10n.commonLoadFailed,
            message: l10n.commonLoadError('$e'),
            action: FButton(
              variant: FButtonVariant.ghost,
              onPress: () => ref.invalidate(accountsStreamProvider),
              child: Text(l10n.commonRetry),
            ),
          ),
          data: (accounts) => _buildForm(accounts),
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
          const SizedBox(height: AppSpacing.s12),

          _buildTypeSelector(),
          const SizedBox(height: AppSpacing.s12),

          AccountPicker(
            accounts: eligible.isEmpty ? accounts : eligible,
            value: _accountId,
            onChanged: (v) => setState(() {
              _accountId = v;
              dirty.markDirty();
            }),
          ),
          if (_type == TradeType.buy || _type == TradeType.sell) ...[
            const SizedBox(height: AppSpacing.s12),
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
          const SizedBox(height: AppSpacing.s12),

          AmountField(
            key: const Key('trade-entry-quantity'),
            label: l10n.tradeEntryQuantityLabel,
            controller: _quantityController,
            focusNode: _quantityFocus,
            onFieldSubmitted: (_) => _priceFocus.requestFocus(),
            helperText: _decimalScaleHint(l10n),
          ),
          const SizedBox(height: AppSpacing.s12),

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
          const SizedBox(height: AppSpacing.s12),

          DateField(
            label: l10n.tradeEntryDateLabel,
            initialValue: _tradeDate,
            required: true,
            includeTime: true,
            onChanged: (d) {
              if (d != null) {
                setState(() {
                  _tradeDate = d;
                  dirty.markDirty();
                });
              }
            },
          ),
          const SizedBox(height: AppSpacing.s12),

          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() {
              _currency = v;
              dirty.markDirty();
            }),
          ),
          const SizedBox(height: AppSpacing.s12),

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
              const SizedBox(width: AppSpacing.s12),
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
          const SizedBox(height: AppSpacing.s12),

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
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
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

/// Build a human-readable narration for a trade when the user did not
/// type a note. Uses the asset symbol + name so the Activity feed shows
/// e.g. "Buy 10 AAPL (Apple Inc.)" instead of the raw asset unit ID.
String _tradeNarration(
  TradeType type,
  Decimal qty,
  Asset asset,
  AppLocalizations l10n,
) {
  final verb = type == TradeType.buy ? l10n.tradeVerbBuy : l10n.tradeVerbSell;
  final symbol = asset.symbol;
  final name = asset.name;
  final qtyStr = _trimQty(qty);
  return name != null && name.trim().isNotEmpty
      ? '$verb $qtyStr $symbol ($name)'
      : '$verb $qtyStr $symbol';
}

String _trimQty(Decimal v) {
  final s = v.toString();
  if (!s.contains('.')) return s;
  final trimmed = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}
