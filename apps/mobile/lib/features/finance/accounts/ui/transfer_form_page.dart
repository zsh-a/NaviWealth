import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/haptics/haptics.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../shared/ui/account_tree_picker.dart';
import '../../shared/ui/forms/forms.dart';
import '../../shared/ui/postings_preview.dart';

/// Records a transfer between two of the user's asset / liability
/// accounts using the [JournalEntryRepository] / [JournalEntryBuilders]
/// stack. When the two accounts hold different currencies the form
/// surfaces a "To amount" input (defaulted from the FX rate book,
/// editable) and the builder attaches a price annotation pinning the
/// user's chosen rate so the JE invariant is satisfied.
class TransferFormPage extends ConsumerStatefulWidget {
  const TransferFormPage({super.key});

  @override
  ConsumerState<TransferFormPage> createState() => _TransferFormPageState();
}

/// Throw-away sync metadata for live preview postings. Never persisted
/// — the values exist only so [Posting]'s constructor accepts the
/// preview rows for rendering.
final SyncMeta _previewSync = SyncMeta(
  ownerUserId: 'preview',
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  updatedByDevice: 'preview',
  hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'preview'),
);

class _TransferFormPageState extends ConsumerState<TransferFormPage>
    with FormSubmission<TransferFormPage>, FormDirtyGuard<TransferFormPage> {
  @override
  String get leaveFallback => FinanceRoutes.wealth;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _toAmountController = TextEditingController();
  final _noteController = TextEditingController();
  final _amountFocus = FocusNode();
  final _toAmountFocus = FocusNode();
  final _noteFocus = FocusNode();
  final _detailsFocus = FocusNode();

  String? _fromAccountId;
  String? _toAccountId;
  late DateTime _date;
  bool _busy = false;
  bool _detailsExpanded = false;

  /// Tracks whether the user has typed into the to-amount field. Until
  /// they do, we keep [_toAmountController] in lock-step with
  /// `amount × defaultFxRate` so the field reads as a live preview;
  /// the moment the user touches it the auto-fill bows out.
  bool _toAmountUserTouched = false;

  @override
  void initState() {
    super.initState();
    _date = ref.read(formClockProvider)();
    // `_toAmountController` is auto-filled from the FX rate, so it must
    // not be bound — only an explicit user edit (tracked by
    // `_onToAmountTyped`) counts as dirty.
    dirty.bindTextControllers([_amountController, _noteController]);
    _toAmountController.addListener(_onToAmountTyped);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _toAmountController.dispose();
    _noteController.dispose();
    _amountFocus.dispose();
    _toAmountFocus.dispose();
    _noteFocus.dispose();
    _detailsFocus.dispose();
    super.dispose();
  }

  void _onToAmountTyped() {
    if (_toAmountFocus.hasFocus && !_toAmountUserTouched) {
      // The autofill writes happen while the field is unfocused, so a
      // change with focus held = the user typed it. The flag stays
      // sticky for the rest of the form's lifecycle.
      setState(() => _toAmountUserTouched = true);
      dirty.markDirty();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    // `?convert=1` query (set by the global action panel's Convert
    // entry) tells us the user wants to exchange currencies inside one
    // account. We surface a banner above the form and pre-select the
    // same account on both sides so they only need to pick currencies.
    final convertMode =
        GoRouter.of(
          context,
        ).routeInformationProvider.value.uri.queryParameters['convert'] ==
        '1';
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(convertMode ? l10n.superFabConvert : l10n.transferTitle),
        confirmLeave: handleBackIntent,
        child: accountsAsync.whenOrLoading(
          context: context,
          data: (accounts) => _buildForm(context, accounts, convertMode),
          error: (_, _) => Center(
            child: AppEmptyState.error(
              title: l10n.commonLoadFailed,
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(accountsStreamProvider),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    List<Account> accounts,
    bool convertMode,
  ) {
    final l10n = AppLocalizations.of(context);
    // Pre-compute the asset+liability subset once so the picker /
    // preview can resolve account names without re-walking per
    // keystroke.
    final transferable = <Account>[
      for (final a in accounts)
        if (a.category == AccountSide.asset ||
            a.category == AccountSide.liability)
          a,
    ];
    final accountsById = <String, Account>{for (final a in accounts) a.id: a};

    final fromAccount = _fromAccountId == null
        ? null
        : accountsById[_fromAccountId!];
    final toAccount = _toAccountId == null ? null : accountsById[_toAccountId!];

    final fromCurrency = fromAccount?.currency;
    final toCurrency = toAccount?.currency;
    final isCrossCurrency =
        fromCurrency != null &&
        toCurrency != null &&
        fromCurrency != toCurrency;

    final amount = readAmount(_amountController);

    // Show a "no FX rate on file" hint when cross-currency and the FX
    // book is empty / silent on this pair. Computed each build off the
    // current amount + currencies, but no controller mutation —
    // controller updates flow through `_refreshToAmountAutofill`,
    // which fires from event handlers, not build, to avoid leaking
    // post-frame timers (which fakeAsync surfaces as a hard test
    // failure).
    final defaultToAmount = (isCrossCurrency && amount != null)
        ? _suggestToAmount(amount: amount, from: fromCurrency, to: toCurrency)
        : null;

    final toAmount = isCrossCurrency
        ? readAmount(_toAmountController) ?? defaultToAmount
        : null;

    final preview = _buildPreview(
      fromId: _fromAccountId,
      toId: _toAccountId,
      amount: amount,
      fromCurrency: fromCurrency,
      toCurrency: toCurrency,
      toAmount: toAmount,
    );

    // Same-account is allowed when the two currencies differ — that's
    // a "Convert" (e.g. exchanging USD → HKD inside one IBKR
    // container). Same-account same-currency is still meaningless and
    // blocked. Cross-account same- or cross-currency is the classic
    // transfer.
    final isSameAccountConvert =
        _fromAccountId != null &&
        _toAccountId != null &&
        _fromAccountId == _toAccountId &&
        isCrossCurrency;
    final isCrossAccount =
        _fromAccountId != null &&
        _toAccountId != null &&
        _fromAccountId != _toAccountId;
    final canSubmit =
        !_busy &&
        (isCrossAccount || isSameAccountConvert) &&
        amount != null &&
        amount > Decimal.zero &&
        (!isCrossCurrency || (toAmount != null && toAmount > Decimal.zero));
    final onSubmit = canSubmit ? _save : null;

    return Form(
      key: _formKey,
      child: AppFormScaffoldBody(
        onSubmit: onSubmit,
        action: SizedBox(
          width: double.infinity,
          child: FButton(
            variant: FButtonVariant.primary,
            onPress: onSubmit,
            child: Text(l10n.transferSubmitAction),
          ),
        ),
        children: [
          if (convertMode)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.s12),
                decoration: BoxDecoration(
                  color: context.theme.colors.primary.withValues(
                    alpha: AppOpacity.subtle,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    Icon(
                      FLucideIcons.arrowLeftRight,
                      size: AppIconSizes.sm,
                      color: context.theme.colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text(
                        l10n.transferConvertModeBanner,
                        style: context.captionStyle.copyWith(
                          color: context.theme.colors.foreground,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          AccountTreePicker(
            accounts: transferable,
            value: _fromAccountId,
            onChanged: (v) {
              setState(() {
                _fromAccountId = v;
                // Picking a new account potentially flips the
                // currency relationship; reset the autofill
                // suppressor so the next paint takes the FX
                // default.
                _toAmountUserTouched = false;
                dirty.markDirty();
              });
              _refreshToAmountAutofill(accountsById);
            },
            category: null,
            label: l10n.transferFromLabel,
            allowSystemAccounts: false,
            validator: (v) => (v == null || v.isEmpty)
                ? l10n.transferValidationRequired
                : null,
          ),
          const SizedBox(height: AppSpacing.s12),
          AccountTreePicker(
            accounts: transferable,
            value: _toAccountId,
            onChanged: (v) {
              setState(() {
                _toAccountId = v;
                _toAmountUserTouched = false;
                dirty.markDirty();
              });
              _refreshToAmountAutofill(accountsById);
            },
            category: null,
            label: l10n.transferToLabel,
            allowSystemAccounts: false,
            validator: (v) {
              if (v == null || v.isEmpty) {
                return l10n.transferValidationRequired;
              }
              if (v == _fromAccountId) {
                return l10n.transferValidationDifferentAccount;
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          AmountField(
            label: fromCurrency == null
                ? l10n.transferAmountLabel
                : l10n.transferAmountWithCurrencyLabel(fromCurrency),
            controller: _amountController,
            currencyCode: fromCurrency,
            focusNode: _amountFocus,
            onChanged: (_) {
              setState(() {});
              _refreshToAmountAutofill(accountsById);
            },
            onFieldSubmitted: (_) {
              if (isCrossCurrency) {
                _toAmountFocus.requestFocus();
              } else {
                _detailsFocus.requestFocus();
              }
            },
          ),
          if (isCrossCurrency) ...[
            const SizedBox(height: AppSpacing.s12),
            AmountField(
              label: l10n.transferToAmountLabel(toCurrency),
              controller: _toAmountController,
              currencyCode: toCurrency,
              focusNode: _toAmountFocus,
              helperText: defaultToAmount == null
                  ? l10n.transferFxRateHelper
                  : l10n.transferFxRateEditHelper,
              onChanged: (_) => setState(() {}),
              onFieldSubmitted: (_) => _detailsFocus.requestFocus(),
            ),
            if (amount != null && toAmount != null && amount > Decimal.zero)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s4),
                child: Text(
                  _rateLabel(
                    amount: amount,
                    toAmount: toAmount,
                    fromCcy: fromCurrency,
                    toCcy: toCurrency,
                  ),
                  style: context.microCaptionStyle,
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.s12),
          FAccordion(
            control: FAccordionControl.lifted(
              expanded: (_) => _detailsExpanded,
              onChange: (_, expanded) =>
                  setState(() => _detailsExpanded = expanded),
            ),
            children: [
              FAccordionItem(
                key: const Key('transfer-details-disclosure'),
                focusNode: _detailsFocus,
                title: Semantics(
                  key: const Key('transfer-details-toggle-label'),
                  expanded: _detailsExpanded,
                  child: Text(l10n.transferDetailsTitle),
                ),
                child: Offstage(
                  offstage: !_detailsExpanded,
                  child: ExcludeFocus(
                    excluding: !_detailsExpanded,
                    child: ExcludeSemantics(
                      excluding: !_detailsExpanded,
                      child: Column(
                        children: [
                          DateField(
                            label: l10n.transferDateLabel,
                            initialValue: _date,
                            required: true,
                            includeTime: true,
                            onChanged: (d) {
                              if (d != null) {
                                setState(() {
                                  _date = d;
                                  dirty.markDirty();
                                });
                              }
                            },
                          ),
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
          ),
          const SizedBox(height: AppSpacing.s16),
          if (preview != null)
            PostingsPreview(
              postings: preview,
              accounts: accountsById,
              title: _noteController.text.isEmpty
                  ? l10n.transferPreviewTitle
                  : _noteController.text,
            ),
        ],
      ),
    );
  }

  /// Look up `amount × fxRate(from → to)` in the in-memory FX book.
  /// Returns `null` when no rate is on file — the form falls back to
  /// "user enters the to-amount manually".
  Decimal? _suggestToAmount({
    required Decimal amount,
    required String from,
    required String to,
  }) {
    final lookup = ref.read(currentFxLookupProvider);
    final fxRate = lookup.rateFor(from, to, on: _date);
    if (fxRate == null) return null;
    // Decimal × Decimal stays Decimal; round to a sensible 6-fraction
    // default so the auto-fill doesn't sprawl across the input.
    return (amount * fxRate.rate).round(scale: 6);
  }

  /// Recompute the to-amount autofill after a change to from/to
  /// account or amount. Pure event-handler driven so we never write
  /// the controller during build (which would leak post-frame
  /// callbacks past pumpAndSettle).
  void _refreshToAmountAutofill(Map<String, Account> byId) {
    if (_toAmountUserTouched) return;
    final fromId = _fromAccountId;
    final toId = _toAccountId;
    if (fromId == null || toId == null) return;
    final from = byId[fromId];
    final to = byId[toId];
    if (from == null || to == null) return;
    if (from.currency == to.currency) {
      // Single-currency: the to-amount field isn't shown; leave the
      // controller content alone.
      return;
    }
    final amount = readAmount(_amountController);
    if (amount == null || amount <= Decimal.zero) {
      // Don't blow away an empty default with another empty value.
      return;
    }
    final suggested = _suggestToAmount(
      amount: amount,
      from: from.currency,
      to: to.currency,
    );
    if (suggested == null) {
      // No rate on file → keep whatever the user already typed.
      return;
    }
    final next = suggested.toString();
    if (_toAmountController.text != next) {
      _toAmountController.text = next;
    }
  }

  /// Renders "1 USD = 7.10 CNY" (or the inverse depending on which
  /// rate reads more naturally given the input amounts).
  String _rateLabel({
    required Decimal amount,
    required Decimal toAmount,
    required String fromCcy,
    required String toCcy,
  }) {
    final l10n = AppLocalizations.of(context);
    final rate = (toAmount / amount).toDecimal(scaleOnInfinitePrecision: 6);
    return l10n.transferRateLabel(fromCcy, rate.toString(), toCcy);
  }

  /// Live PostingsPreview source — produces a draft list mirroring
  /// what `_save()` will commit, so the user sees the exact ledger
  /// shape before pressing Transfer. Returns `null` while the form
  /// isn't yet fillable enough to render meaningful legs.
  List<Posting>? _buildPreview({
    required String? fromId,
    required String? toId,
    required Decimal? amount,
    required String? fromCurrency,
    required String? toCurrency,
    required Decimal? toAmount,
  }) {
    if (fromId == null ||
        toId == null ||
        fromId == toId ||
        amount == null ||
        amount <= Decimal.zero ||
        fromCurrency == null ||
        toCurrency == null) {
      return null;
    }
    final isCross = fromCurrency != toCurrency;
    if (isCross && (toAmount == null || toAmount <= Decimal.zero)) {
      return null;
    }
    final build = JournalEntryBuilders.transfer(
      date: _date,
      fromAccountId: fromId,
      toAccountId: toId,
      amount: amount,
      currency: fromCurrency,
      toAmount: isCross ? toAmount : null,
      toCurrency: isCross ? toCurrency : null,
      narration: _noteController.text.isEmpty ? null : _noteController.text,
    );
    return _materialise(build.postings);
  }

  /// Adapt builder drafts into [Posting]s the read-only preview can
  /// consume. The repo would mint real ids + sync stamps on commit;
  /// the preview only needs the column shape for rendering, so we
  /// hand-roll a stub `SyncMeta` that never escapes this widget.
  List<Posting> _materialise(List<PostingDraft> drafts) {
    return [
      for (var i = 0; i < drafts.length; i++)
        Posting(
          id: 'preview-$i',
          journalEntryId: 'preview',
          position: drafts[i].position ?? i,
          accountId: drafts[i].accountId,
          units: drafts[i].units,
          unit: drafts[i].unit,
          cost: drafts[i].cost,
          price: drafts[i].price,
          sync: _previewSync,
        ),
    ];
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = readAmount(_amountController);
    if (amount == null ||
        amount <= Decimal.zero ||
        _fromAccountId == null ||
        _toAccountId == null) {
      Haptics.error();
      return;
    }
    final accounts = ref.read(accountsStreamProvider).asData?.value ?? const [];
    final byId = <String, Account>{for (final a in accounts) a.id: a};
    final fromCcy = byId[_fromAccountId!]?.currency;
    final toCcy = byId[_toAccountId!]?.currency;
    if (fromCcy == null || toCcy == null) {
      Haptics.error();
      return;
    }
    final isCross = fromCcy != toCcy;
    Decimal? toAmount;
    if (isCross) {
      toAmount = readAmount(_toAmountController);
      if (toAmount == null || toAmount <= Decimal.zero) {
        Haptics.error();
        return;
      }
    }

    final l10n = AppLocalizations.of(context);
    final note = _noteController.text.trim();
    final build = JournalEntryBuilders.transfer(
      date: _date,
      fromAccountId: _fromAccountId!,
      toAccountId: _toAccountId!,
      amount: amount,
      currency: fromCcy,
      toAmount: isCross ? toAmount : null,
      toCurrency: isCross ? toCcy : null,
      narration: note.isEmpty ? null : note,
    );
    late JournalEntryRepository repository;
    await submitFormAndLeave<JournalMutationReceipt>(
      dirty: dirty,
      onBusyChanged: _setBusy,
      leaveFallback: FinanceRoutes.wealth,
      commit: () async {
        final repo = await ref.read(journalEntryRepositoryProvider.future);
        repository = repo;
        return repo.createWithReceipt(
          entry: build.entry,
          postings: build.postings,
        );
      },
      failureMessage: (e) => switch (e) {
        JournalEntryUnbalancedException(:final message) =>
          l10n.transferRejectedError(message),
        _ => l10n.transferFailedError('$e'),
      },
      successMessage: l10n.commonSaved,
      undo: FormUndoPresentation<JournalMutationReceipt>(
        buildAction: (receipt) =>
            FormUndoAction(() => repository.undoMutation(receipt)),
        actionLabel: l10n.commonUndo,
        successMessage: l10n.commonUndoSucceeded,
        failureMessage: (_) => l10n.commonUndoFailed,
        retryLabel: l10n.commonRetry,
      ),
      tag: 'transfer-form',
    );
  }

  void _setBusy(bool value) {
    if (mounted && _busy != value) setState(() => _busy = value);
  }
}
