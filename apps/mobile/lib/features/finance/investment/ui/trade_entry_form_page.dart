import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:uuid/uuid.dart';

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
    this.initialType,
  });

  /// Pre-selected asset id. When null the user picks via [SymbolField].
  final String? assetId;

  /// Pre-selected account id.
  final String? accountId;

  /// Optional values supplied by an upstream workflow, such as rebalance.
  final TradeEntryPrefill? prefill;

  /// Optional side supplied by a contextual Buy/Sell action.
  final TradeType? initialType;

  @override
  ConsumerState<TradeEntryFormPage> createState() => _TradeEntryFormPageState();
}

class _TradeEntryFormPageState extends ConsumerState<TradeEntryFormPage>
    with
        FormSubmission<TradeEntryFormPage>,
        FormDirtyGuard<TradeEntryFormPage> {
  @override
  String get leaveFallback => FinanceRoutes.activity;

  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _feeController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');
  final _noteController = TextEditingController();
  final String _transactionId = const Uuid().v4();

  // Focus chain: quantity → price → fee → tax → note. Submit fires from
  // the last `done` action so the user can complete an entry without
  // ever lifting their thumb to tap fields. The wrap into a list keeps
  // dispose tidy.
  final _quantityFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _feeFocus = FocusNode();
  final _taxFocus = FocusNode();
  final _noteFocus = FocusNode();
  final _settlementFocus = FocusNode(debugLabel: 'trade-settlement');
  final _advancedFocus = FocusNode(debugLabel: 'trade-advanced');

  TradeType _type = TradeType.buy;
  String? _accountId;
  String? _cashAccountId;
  String? _currency;
  late DateTime _tradeDate;
  LocalSecurityChoice? _selected;
  bool _busy = false;
  bool _hydratedDefaults = false;
  bool _currencyExplicitlySelected = false;
  bool _cashCurrencyResolved = false;
  bool _cashAccountClearedForCurrency = false;
  bool _showSettlementDetails = false;
  bool _showAdvancedDetails = false;

  // transferIn / transferOut are deliberately absent from this form —
  // they can never be created as a single user-entered leg.
  // `TransferFormPage` (under `/activity/accounts/transfer`) writes the two
  // legs atomically via `JournalEntryRepository`.
  static const _tradeTypes = [TradeType.buy, TradeType.sell];

  String _typeLabel(AppLocalizations l10n, TradeType type) {
    return switch (type) {
      TradeType.buy => l10n.tradeTypeBuy,
      TradeType.sell => l10n.tradeTypeSell,
      TradeType.valuationAdjust => l10n.tradeTypeValuationAdjust,
    };
  }

  String _typeCompactLabel(AppLocalizations l10n, TradeType type) {
    return switch (type) {
      TradeType.buy => l10n.tradeTypeBuy,
      TradeType.sell => l10n.tradeTypeSell,
      TradeType.valuationAdjust => l10n.tradeTypeAdjustShort,
    };
  }

  @override
  void initState() {
    super.initState();
    _tradeDate = ref.read(formClockProvider)();
    _currency = ref.read(baseCurrencyProvider);
    _type = widget.initialType ?? _type;
    // Constructor-supplied pre-selection wins over the persisted default.
    _accountId = widget.accountId;
    final defaults = ref.read(formDefaultsProvider);
    _accountId ??= defaults.tradeAccountId;
    _cashAccountId = defaults.tradeCashAccountId;
    final prefill = widget.prefill;
    if (prefill != null) {
      _cashCurrencyResolved = true;
      _type = prefill.type;
      _currency = prefill.currency;
      _tradeDate = prefill.tradeDate ?? _tradeDate;
      _quantityController.text = prefill.quantity.toString();
      _priceController.text = prefill.price?.toString() ?? '';
      _feeController.text = prefill.fee?.toString() ?? '0';
      _taxController.text = prefill.tax?.toString() ?? '0';
      _noteController.text = prefill.note ?? '';
      if (prefill.symbol case final symbol?) {
        _selected = LocalSecurityChoice(
          symbol: symbol,
          market: prefill.market ?? inferAssetMarket(symbol),
          type: prefill.market == AssetMarket.crypto
              ? AssetType.crypto
              : AssetType.stock,
          currency: prefill.currency,
          fromCatalog: false,
        );
      }
    }
    if (widget.assetId != null) unawaited(_hydrateInitialAsset());
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

  Future<void> _hydrateInitialAsset() async {
    final assetId = widget.assetId;
    if (assetId == null || assetId.isEmpty) return;
    try {
      final repo = await ref.read(securitiesAssetRepositoryProvider.future);
      final asset = await repo.findById(assetId);
      if (!mounted || asset == null) return;
      final choice = LocalSecurityChoice(
        symbol: asset.symbol,
        market: assetMarketFromWire(asset.market) ?? AssetMarket.unknown,
        type: asset.type,
        currency: asset.currency,
        fromCatalog: true,
        name: asset.name,
        isin: asset.isin,
      );
      setState(() {
        _selected = choice;
        _cashCurrencyResolved = true;
        if (!_currencyExplicitlySelected) _currency = choice.currency;
      });
    } catch (_) {
      // Contextual prefill is a convenience. The searchable field remains
      // available if the referenced asset was removed or cannot be loaded.
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
    _settlementFocus.dispose();
    _advancedFocus.dispose();
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
    if (_busy) return;
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

    final type = _type;
    final tradeDate = _tradeDate;
    // Normalise zero to null so the JE builder's _normalizeOptionalAmount
    // doesn't reject a user-entered "0" as an invalid positive amount.
    final fee = _nonZeroOr(Decimal.tryParse(_feeController.text.trim()));
    final tax = _nonZeroOr(Decimal.tryParse(_taxController.text.trim()));
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    String failureMessage(Object error) {
      if (error is TradeSubmissionContractError) {
        switch (error.code) {
          case TradeSubmissionContractErrorCode.accountInvalid:
            return l10n.tradeEntryBrokerAccountRequiredMessage;
          case TradeSubmissionContractErrorCode.cashAccountInvalid:
            return l10n.tradeEntryCashAccountInvalid;
          case TradeSubmissionContractErrorCode.lotCurrencyMismatch:
            return l10n.tradeEntryLotCurrencyMismatch;
          default:
            break;
        }
      }
      return l10n.tradeEntryFailure(
        error is TradeEntryException
            ? error.message
            : userSafeErrorMessage(
                context,
                error,
                operation: 'record trade',
                logError: false,
              ),
      );
    }

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

    late final TradeEntrySubmissionService submissionService;
    final preflightTimeout = ref.read(tradeEntryPreflightTimeoutProvider);
    final logger = ref.read(loggerProvider);
    final operation = logger.startOperation(
      'finance.trade.submit',
      fields: {
        'trade_type': type,
        'asset_type': selected.type,
        'market': selected.market,
        'has_price': price != null,
        'has_cash_account': _cashAccountId != null,
      },
    );
    _setBusy(true);
    dirty.busy = true;
    try {
      submissionService = await operation.step(
        'resolve_dependencies',
        () => ref
            .read(tradeEntrySubmissionServiceProvider.future)
            .timeout(preflightTimeout),
        slowThreshold: const Duration(seconds: 1),
      );
      if (!mounted) {
        operation.cancel(stage: 'resolve_dependencies');
        return;
      }

      // For buys with a known price, check whether the cash account would
      // go negative and prompt the user to confirm.
      if (type == TradeType.buy && price != null) {
        final cashOut =
            quantity * price + (fee ?? Decimal.zero) + (tax ?? Decimal.zero);
        final cashAccountId = _cashAccountId ?? accountId;
        final currentBalance = await operation.step(
          'check_cash_balance',
          () => submissionService
              .balanceByAccountUnit(cashAccountId, currency)
              .timeout(preflightTimeout),
          slowThreshold: const Duration(seconds: 1),
        );
        if (!mounted) {
          operation.cancel(stage: 'check_cash_balance');
          return;
        }
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
          logger.event(
            'finance.trade.submit.confirmation.completed',
            operationId: operation.operationId,
            fields: {
              'stage': 'cash_overdraw_confirmation',
              'outcome': confirmed == true ? 'confirmed' : 'cancelled',
            },
          );
          if (confirmed != true) {
            operation.cancel(stage: 'cash_overdraw_confirmation');
            return;
          }
        }
      }
    } catch (error, stack) {
      if (error is TimeoutException) {
        // A FutureProvider keeps its in-flight/error state. Drop only this
        // composition provider so Retry builds a fresh dependency graph.
        ref.invalidate(tradeEntrySubmissionServiceProvider);
      }
      operation.fail(
        error,
        stackTrace: stack,
        stage: 'preflight',
        retryable: true,
      );
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          failureMessage(error),
          duration: const Duration(seconds: 6),
        );
      }
      return;
    } finally {
      dirty.busy = false;
      _setBusy(false);
    }

    await submitForm<TradeMutationReceipt>(
      dirty: dirty,
      onBusyChanged: _setBusy,
      // Use the underlying Navigator (rather than `context.pop()`) so the
      // form is portable to test surfaces that mount it without a router.
      // GoRouter sub-routes sit on the same Navigator stack, so this is
      // a no-op difference in production.
      leave: () => Navigator.of(context).pop(true),
      tag: 'trade-entry',
      diagnosticOperation: operation,
      // `TradeEntryException` carries a user-facing message; pass it
      // through so the snackbar reads "Couldn't record trade: <reason>"
      // instead of a generic "save failed".
      failureMessage: failureMessage,
      successMessage: l10n.commonSaved,
      undo: FormUndoPresentation<TradeMutationReceipt>(
        buildAction: (receipt) =>
            FormUndoAction(() => submissionService.undoMutation(receipt)),
        actionLabel: l10n.commonUndo,
        successMessage: l10n.commonUndoSucceeded,
        failureMessage: (_) => l10n.commonUndoFailed,
        retryLabel: l10n.commonRetry,
      ),
      commit: () => submissionService.submit(
        TradeEntrySubmissionRequest(
          transactionId: _transactionId,
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
        diagnosticOperation: operation,
      ),
    );
  }

  void _setBusy(bool value) {
    if (mounted && _busy != value) setState(() => _busy = value);
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
          context: context,
          error: (e, _) => AppEmptyState.error(
            title: l10n.commonLoadFailed,
            message: userSafeErrorMessage(context, e),
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(accountsStreamProvider),
          ),
          data: (accounts) => _buildForm(accounts),
        ),
      ),
    );
  }

  Widget _buildForm(List<Account> accounts) {
    final l10n = AppLocalizations.of(context);
    final onSubmit = _busy ? null : _submit;
    final eligible = accounts
        .where(
          (a) =>
              a.type == AccountCategory.broker ||
              a.type == AccountCategory.crypto,
        )
        .toList(growable: false);

    if (eligible.isEmpty) {
      return AppEmptyState(
        icon: FLucideIcons.landmark,
        title: l10n.tradeEntryBrokerAccountRequiredTitle,
        message: l10n.tradeEntryBrokerAccountRequiredMessage,
        action: FButton(
          variant: FButtonVariant.primary,
          onPress: () => context.push(FinanceRoutes.wealthAccountNew),
          prefix: const Icon(FLucideIcons.creditCard),
          child: Text(l10n.accountFormCreateTitle),
        ),
      );
    }

    // Fall back to the first eligible account once we know the workspace
    // contents. Only fires once per page mount so the user can deliberately
    // clear the picker without us re-imposing a default.
    if (!_hydratedDefaults) {
      final pool = eligible;
      if (_accountId == null && pool.isNotEmpty) {
        _accountId = pool.first.id;
      } else if (_accountId != null && !pool.any((a) => a.id == _accountId)) {
        _accountId = pool.isEmpty ? null : pool.first.id;
      }
      if (_cashCurrencyResolved &&
          _cashAccountId != null &&
          !_cashAccounts(accounts).any((a) => a.id == _cashAccountId)) {
        _cashAccountId = null;
      }
      _hydratedDefaults = true;
    }

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: AppFormScaffoldBody(
        onSubmit: onSubmit,
        action: SizedBox(
          width: double.infinity,
          child: AppBusyButton(
            buttonKey: const Key('trade-entry-submit'),
            label: l10n.commonSave,
            busyLabel: l10n.commonSaving,
            busy: _busy,
            onPress: onSubmit,
          ),
        ),
        children: [
          if (submissionFailureMessage != null) ...[
            AppStatusBanner(
              kind: AppStatusKind.error,
              message: submissionFailureMessage!,
              icon: FLucideIcons.circleAlert,
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          _buildAssetSearch(accounts),
          const SizedBox(height: AppSpacing.s12),

          _buildTypeSelector(),
          const SizedBox(height: AppSpacing.s12),

          AccountPicker(
            key: const Key('trade-entry-account'),
            label: l10n.tradeEntryHoldingAccountLabel,
            accounts: eligible,
            value: _accountId,
            onChanged: (v) => setState(() {
              _accountId = v;
              dirty.markDirty();
            }),
          ),
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
          ),
          const SizedBox(height: AppSpacing.s12),

          if (_type == TradeType.buy || _type == TradeType.sell)
            _buildSettlementSection(accounts)
          else
            CurrencyPicker(
              key: const Key('trade-entry-currency'),
              value: _currency,
              onChanged: (v) => _changeCurrency(v, accounts, explicit: true),
            ),
          const SizedBox(height: AppSpacing.s12),
          _buildAdvancedSection(),
        ],
      ),
    );
  }

  Widget _buildAdvancedSection() {
    final l10n = AppLocalizations.of(context);
    final hasCosts =
        _feeController.text.trim() != '0' || _taxController.text.trim() != '0';
    final hasNote = _noteController.text.trim().isNotEmpty;
    final summary = hasCosts || hasNote
        ? l10n.tradeEntryAdvancedConfigured
        : l10n.tradeEntryAdvancedSummary;
    return FAccordion(
      control: FAccordionControl.lifted(
        expanded: (_) => _showAdvancedDetails,
        onChange: (_, expanded) =>
            setState(() => _showAdvancedDetails = expanded),
      ),
      children: [
        FAccordionItem(
          key: const Key('trade-entry-advanced-summary'),
          focusNode: _advancedFocus,
          title: _disclosureTitle(
            key: const Key('trade-entry-advanced-toggle-label'),
            icon: FLucideIcons.slidersHorizontal,
            title: l10n.tradeEntryAdvancedTitle,
            summary: summary,
            expanded: _showAdvancedDetails,
          ),
          child: Offstage(
            key: const Key('trade-entry-advanced-details'),
            offstage: !_showAdvancedDetails,
            child: ExcludeFocus(
              excluding: !_showAdvancedDetails,
              child: ExcludeSemantics(
                excluding: !_showAdvancedDetails,
                child: Column(
                  children: [
                    DateField(
                      label: l10n.tradeEntryDateLabel,
                      initialValue: _tradeDate,
                      required: true,
                      includeTime: true,
                      onChanged: (date) {
                        if (date == null) return;
                        setState(() {
                          _tradeDate = date;
                          dirty.markDirty();
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _buildTradeCosts(l10n),
                    const SizedBox(height: AppSpacing.s12),
                    NoteField(
                      controller: _noteController,
                      focusNode: _noteFocus,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTradeCosts(AppLocalizations l10n) {
    final feeField = AmountField(
      key: const Key('trade-entry-fee'),
      label: l10n.tradeEntryFeeLabel,
      controller: _feeController,
      currencyCode: _currency,
      required: false,
      focusNode: _feeFocus,
      onFieldSubmitted: (_) => _taxFocus.requestFocus(),
    );
    final taxField = AmountField(
      key: const Key('trade-entry-tax'),
      label: l10n.tradeEntryTaxLabel,
      controller: _taxController,
      currencyCode: _currency,
      required: false,
      focusNode: _taxFocus,
      onFieldSubmitted: (_) => _noteFocus.requestFocus(),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledBodySize = MediaQuery.textScalerOf(context).scale(16);
        final stackFields = scaledBodySize >= 24 || constraints.maxWidth < 320;
        if (stackFields) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              feeField,
              const SizedBox(height: AppSpacing.s12),
              taxField,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: feeField),
            const SizedBox(width: AppSpacing.s12),
            Expanded(child: taxField),
          ],
        );
      },
    );
  }

  Widget _disclosureTitle({
    required Key key,
    required IconData icon,
    required String title,
    required String summary,
    required bool expanded,
  }) {
    return Semantics(
      key: key,
      expanded: expanded,
      child: Row(
        children: [
          AppIconTile(icon: icon, color: context.theme.colors.primary),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(summary, style: context.captionStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementSection(List<Account> accounts) {
    final l10n = AppLocalizations.of(context);
    final currency = _currency ?? '—';
    Account? cashAccount;
    for (final account in accounts) {
      if (account.id == _cashAccountId) {
        cashAccount = account;
        break;
      }
    }
    final summary = cashAccount == null
        ? l10n.tradeEntrySettlementBrokerCash(currency)
        : l10n.tradeEntrySettlementExternal(cashAccount.name, currency);
    final assetCurrency = _selected?.currency;
    final isCrossCurrency =
        assetCurrency != null &&
        assetCurrency.toUpperCase() != currency.toUpperCase();

    return FAccordion(
      control: FAccordionControl.lifted(
        expanded: (_) => _showSettlementDetails,
        onChange: (_, expanded) =>
            setState(() => _showSettlementDetails = expanded),
      ),
      children: [
        FAccordionItem(
          key: const Key('trade-entry-settlement-summary'),
          focusNode: _settlementFocus,
          title: _disclosureTitle(
            key: const Key('trade-entry-settlement-toggle-label'),
            icon: FLucideIcons.landmark,
            title: l10n.tradeEntrySettlementTitle,
            summary: summary,
            expanded: _showSettlementDetails,
          ),
          child: Offstage(
            key: const Key('trade-entry-settlement-details'),
            offstage: !_showSettlementDetails,
            child: ExcludeFocus(
              excluding: !_showSettlementDetails,
              child: ExcludeSemantics(
                excluding: !_showSettlementDetails,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CurrencyPicker(
                      key: const Key('trade-entry-currency'),
                      value: _currency,
                      onChanged: (v) =>
                          _changeCurrency(v, accounts, explicit: true),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    AccountPicker(
                      key: const Key('trade-entry-cash-account'),
                      label: l10n.tradeEntrySettlementAccountLabel,
                      accounts: _cashAccounts(accounts),
                      value: _cashAccountId,
                      onChanged: (v) => setState(() {
                        _cashAccountId = v;
                        _cashAccountClearedForCurrency = false;
                        dirty.markDirty();
                      }),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      l10n.tradeEntrySettlementHelper,
                      style: context.captionStyle,
                    ),
                    if (isCrossCurrency) ...[
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        l10n.tradeEntryCrossCurrencyHint(
                          assetCurrency,
                          currency,
                        ),
                        style: context.mutedLabelStyle.copyWith(
                          color: SemanticColors.of(context).warning,
                        ),
                      ),
                    ],
                    if (_cashAccountClearedForCurrency) ...[
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        l10n.tradeEntryCashAccountCurrencyChanged,
                        style: context.mutedLabelStyle.copyWith(
                          color: SemanticColors.of(context).warning,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Account> _cashAccounts(List<Account> accounts) => accounts
      .where(
        (account) =>
            (account.type == AccountCategory.bank ||
                account.type == AccountCategory.cash) &&
            account.currency == _currency,
      )
      .toList(growable: false);

  void _changeCurrency(
    String? value,
    List<Account> accounts, {
    required bool explicit,
  }) {
    setState(() {
      _currency = value;
      if (explicit) {
        _currencyExplicitlySelected = true;
        _cashCurrencyResolved = true;
      }
      final cashAccountId = _cashAccountId;
      if (cashAccountId != null &&
          !_cashAccounts(accounts).any((a) => a.id == cashAccountId)) {
        _cashAccountId = null;
        _cashAccountClearedForCurrency = true;
      }
      dirty.markDirty();
    });
  }

  Widget _buildAssetSearch(List<Account> accounts) {
    return SymbolField(
      key: ValueKey<String>('trade-symbol-${_selected?.symbol ?? 'empty'}'),
      initialValue: _selected,
      onChanged: (choice) {
        setState(() {
          _selected = choice;
          dirty.markDirty();
          if (choice != null) _cashCurrencyResolved = true;
          if (choice != null && !_currencyExplicitlySelected) {
            _currency = choice.currency;
            final cashAccountId = _cashAccountId;
            if (cashAccountId != null &&
                !_cashAccounts(accounts).any((a) => a.id == cashAccountId)) {
              _cashAccountId = null;
              _cashAccountClearedForCurrency = true;
            }
          }
          if (choice != null) {
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
    return SegmentedRow<TradeType>(
      options: _tradeTypes,
      value: _type,
      labelOf: (type) => _typeCompactLabel(l10n, type),
      semanticLabelOf: (type) => _typeLabel(l10n, type),
      onChanged: (type) => setState(() {
        _type = type;
        dirty.markDirty();
      }),
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
