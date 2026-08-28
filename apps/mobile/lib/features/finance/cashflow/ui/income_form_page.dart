import 'dart:async';

import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/accounts/domain/account_semantics.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

enum _IncomeCategory { salary, dividend, interest, other }

/// Quick-entry page for a one-off cash income.
///
/// Income already has a balanced journal builder and seeded counter accounts;
/// this page exposes that existing write path to the same Activity quick-add
/// flow as expenses. The user only chooses the useful concepts (type,
/// destination account, amount and optional details); ledger account names
/// stay an implementation detail.
class IncomeFormPage extends ConsumerStatefulWidget {
  const IncomeFormPage({super.key});

  @override
  ConsumerState<IncomeFormPage> createState() => _IncomeFormPageState();
}

class _IncomeFormPageState extends ConsumerState<IncomeFormPage>
    with FormSubmission<IncomeFormPage>, FormDirtyGuard<IncomeFormPage> {
  @override
  String get leaveFallback => FinanceRoutes.activity;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _amountFocus = FocusNode();
  final _noteFocus = FocusNode();
  final _advancedFocus = FocusNode(debugLabel: 'income-advanced');

  _IncomeCategory _category = _IncomeCategory.salary;
  String? _toAccountId;
  String? _currency;
  late DateTime _date;
  bool _advancedExpanded = false;
  bool _busy = false;
  bool _accountsHydrated = false;
  late final ProviderSubscription<AsyncValue<List<Account>>>
  _accountsSubscription;

  @override
  void initState() {
    super.initState();
    _date = ref.read(formClockProvider)();
    final defaults = ref.read(formDefaultsProvider);
    _toAccountId = defaults.incomeAccountId;
    _currency = defaults.incomeCurrency ?? ref.read(baseCurrencyProvider);
    dirty.bindTextControllers([_amountController, _noteController]);
    _accountsSubscription = ref.listenManual(
      accountsStreamProvider,
      _onAccounts,
      fireImmediately: true,
    );
  }

  List<Account> _incomeAccounts(List<Account> accounts) => accounts
      .where(
        (account) =>
            !account.archived && isCustodyAccountCategory(account.type),
      )
      .toList(growable: false);

  void _onAccounts(
    AsyncValue<List<Account>>? _,
    AsyncValue<List<Account>> next,
  ) {
    final accounts = next.value;
    if (accounts == null || _accountsHydrated) return;
    final candidates = _incomeAccounts(accounts);
    if (candidates.isEmpty) return;
    final remembered = candidates
        .where((account) => account.id == _toAccountId)
        .firstOrNull;
    final selected = remembered ?? candidates.firstOrNull;
    if (selected != null) {
      _toAccountId = selected.id;
      _currency = selected.currency;
    }
    _accountsHydrated = true;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _accountsSubscription.close();
    _amountController.dispose();
    _noteController.dispose();
    _amountFocus.dispose();
    _noteFocus.dispose();
    _advancedFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final amount = readAmount(_amountController);
    if (amount == null || amount <= Decimal.zero) {
      AppMessenger.show(context, ToastKind.error, l10n.incomeFormAmountInvalid);
      return;
    }
    final toAccountId = _toAccountId;
    final currency = _currency;
    if (toAccountId == null || currency == null || currency.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.incomeFormAccountRequired,
      );
      return;
    }
    final note = _noteController.text.trim();
    final date = _date;
    final category = _category;
    late JournalEntryRepository repository;
    unawaited(
      ref
          .read(formDefaultsProvider.notifier)
          .rememberIncome(accountId: toAccountId, currency: currency),
    );
    await submitFormAndLeave<JournalMutationReceipt>(
      dirty: dirty,
      onBusyChanged: _setBusy,
      leaveFallback: FinanceRoutes.activity,
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.commonSaved,
      undo: FormUndoPresentation<JournalMutationReceipt>(
        buildAction: (receipt) =>
            FormUndoAction(() => repository.undoMutation(receipt)),
        actionLabel: l10n.commonUndo,
        successMessage: l10n.commonUndoSucceeded,
        failureMessage: (_) => l10n.commonUndoFailed,
        retryLabel: l10n.commonRetry,
      ),
      tag: 'income',
      commit: () async {
        final ownerUserId = await ref.read(currentUserIdProvider)();
        final incomeAccountId = AccountRepository.systemAccountIdForPath(
          'income:${category.name}',
          ownerUserId: ownerUserId,
        );
        final build = JournalEntryBuilders.income(
          date: date,
          toAccountId: toAccountId,
          incomeAccountId: incomeAccountId,
          amount: amount,
          currency: currency,
          narration: note.isEmpty ? l10n.incomeFormDefaultNarration : note,
        );
        repository = await ref.read(journalEntryRepositoryProvider.future);
        return repository.createWithReceipt(
          entry: build.entry,
          postings: build.postings,
        );
      },
    );
  }

  void _setBusy(bool value) {
    if (mounted && _busy != value) setState(() => _busy = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final onSubmit = _busy ? null : _save;
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(l10n.incomeFormCreateTitle),
        confirmLeave: handleBackIntent,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: AppFormScaffoldBody(
            onSubmit: onSubmit,
            action: SizedBox(
              width: double.infinity,
              child: AppBusyButton(
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
              AmountField(
                label: l10n.incomeFormAmountLabel,
                controller: _amountController,
                currencyCode: _currency,
                allowZero: false,
                focusNode: _amountFocus,
              ),
              const SizedBox(height: AppSpacing.s12),
              FSelect<_IncomeCategory>(
                items: {
                  l10n.cashFlowKindSalary: _IncomeCategory.salary,
                  l10n.cashFlowKindDividend: _IncomeCategory.dividend,
                  l10n.cashFlowKindInterest: _IncomeCategory.interest,
                  l10n.cashFlowKindOtherIncome: _IncomeCategory.other,
                },
                control: FSelectControl<_IncomeCategory>.managed(
                  initial: _category,
                  onChange: (value) {
                    if (value == null) return;
                    setState(() {
                      _category = value;
                      dirty.markDirty();
                    });
                  },
                ),
                label: RequiredLabel(l10n.incomeFormKindLabel),
              ),
              const SizedBox(height: AppSpacing.s12),
              accountsAsync.when(
                data: (accounts) {
                  final candidates = _incomeAccounts(accounts);
                  if (candidates.isEmpty) {
                    return _NoIncomeAccountsHint();
                  }
                  final selected = candidates
                      .where((account) => account.id == _toAccountId)
                      .firstOrNull;
                  return AccountPicker(
                    accounts: candidates,
                    value: selected?.id,
                    label: l10n.incomeFormAccountLabel,
                    onChanged: (value) {
                      final account = candidates
                          .where((item) => item.id == value)
                          .firstOrNull;
                      setState(() {
                        _toAccountId = value;
                        if (account != null) _currency = account.currency;
                        dirty.markDirty();
                      });
                    },
                  );
                },
                loading: () => const FProgress(),
                error: (error, stackTrace) => Text(
                  userSafeErrorMessage(context, error),
                  style: context.captionStyle.copyWith(
                    color: context.appTheme.status.danger.fg,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              FAccordion(
                control: FAccordionControl.lifted(
                  expanded: (_) => _advancedExpanded,
                  onChange: (_, expanded) =>
                      setState(() => _advancedExpanded = expanded),
                ),
                children: [
                  FAccordionItem(
                    key: const Key('income-advanced-disclosure'),
                    focusNode: _advancedFocus,
                    title: Semantics(
                      expanded: _advancedExpanded,
                      child: Text(l10n.incomeFormAdvancedTitle),
                    ),
                    child: Offstage(
                      offstage: !_advancedExpanded,
                      child: ExcludeFocus(
                        excluding: !_advancedExpanded,
                        child: ExcludeSemantics(
                          excluding: !_advancedExpanded,
                          child: Column(
                            children: [
                              DateField(
                                label: l10n.incomeFormDateLabel,
                                initialValue: _date,
                                required: true,
                                includeTime: true,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _date = value;
                                    dirty.markDirty();
                                  });
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
            ],
          ),
        ),
      ),
    );
  }
}

class _NoIncomeAccountsHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FLucideIcons.wallet,
            size: AppIconSizes.h18,
            color: context.appTheme.status.warning.fg,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.incomeFormNoAccountsTitle, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.incomeFormNoAccountsBody,
                  style: context.captionStyle,
                ),
                const SizedBox(height: AppSpacing.s8),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => context.push(FinanceRoutes.wealthAccountNew),
                  child: Text(l10n.incomeFormNoAccountsCta),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
