import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics/haptics.dart';
import '../../../data/domain/enums.dart';
import '../../../data/repositories/journal_entry_builders.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/journal_entry_repository.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import 'category_grid_picker.dart';

/// Quick-entry page for a single expense. Shared between create and
/// edit flows — when [expenseId] is non-null we hydrate the form from
/// the journal entry the id refers to and call `replacePostings` on
/// save; otherwise we call `JournalEntryRepository.create`.
class ExpenseFormPage extends ConsumerStatefulWidget {
  const ExpenseFormPage({super.key, this.expenseId});

  final String? expenseId;

  bool get isEdit => expenseId != null;

  @override
  ConsumerState<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _ExpenseFormPageState extends ConsumerState<ExpenseFormPage>
    with OptimisticFormSubmit<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  final _amountFocus = FocusNode();
  final _noteFocus = FocusNode();

  /// The expense account id (from the `accounts` table where category=expense).
  String? _expenseAccountId;
  String? _fromAccountId;
  String? _currency = 'CNY';
  DateTime _date = DateTime.now();
  bool _busy = false;
  JournalEntryWithPostings? _initial;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) {
      _loadInitial();
    } else {
      final defaults = ref.read(formDefaultsProvider);
      _fromAccountId = defaults.expenseAccountId;
      _expenseAccountId = defaults.expenseCategoryId;
      if (defaults.expenseCurrency != null &&
          defaults.expenseCurrency!.isNotEmpty) {
        _currency = defaults.expenseCurrency;
      }
    }
  }

  Future<void> _loadInitial() async {
    final journalRepo = await ref.read(journalEntryRepositoryProvider.future);
    final existing = await journalRepo.getById(widget.expenseId!);
    if (existing == null) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.expenseFormLoadError,
      );
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    if (!mounted) return;
    String? expenseAccountId;
    String? fromAccountId;
    Decimal amount = Decimal.zero;
    String currency = 'CNY';
    for (final p in existing.postings) {
      if (p.units > Decimal.zero) {
        expenseAccountId = p.accountId;
        amount = p.units;
        currency = p.unit;
      } else {
        fromAccountId = p.accountId;
      }
    }
    setState(() {
      _initial = existing;
      _amountController.text = amount.toString();
      _noteController.text = existing.entry.narration;
      _expenseAccountId = expenseAccountId;
      _fromAccountId = fromAccountId;
      _currency = currency;
      _date = existing.entry.date;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final amount = readAmount(_amountController);
    if (amount == null || amount <= Decimal.zero) {
      Haptics.error();
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.expenseFormAmountInvalid,
      );
      return;
    }
    if (_expenseAccountId == null || _fromAccountId == null || _currency == null) {
      Haptics.error();
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.expenseFormCategoryAccountRequired,
      );
      return;
    }
    setState(() => _busy = true);
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    final fromAccountId = _fromAccountId!;
    final expenseAccountId = _expenseAccountId!;
    final currency = _currency!;
    final date = _date;
    final initial = _initial;
    if (!mounted) return;
    unawaited(
      ref
          .read(formDefaultsProvider.notifier)
          .rememberExpense(
            accountId: fromAccountId,
            categoryId: expenseAccountId,
            currency: currency,
          ),
    );
    await submitOptimistic(
      pop: () {
        Haptics.success();
        context.go('/activity/expenses');
      },
      tag: 'expense',
      failureMessage: (_) => l10n.commonSaveFailed,
      retryLabel: l10n.commonRetry,
      write: () async {
        final journalRepo = await ref.read(
          journalEntryRepositoryProvider.future,
        );
        final build = JournalEntryBuilders.expense(
          date: date,
          expenseAccountId: expenseAccountId,
          fromAccountId: fromAccountId,
          amount: amount,
          currency: currency,
          narration: note,
        );
        if (initial == null) {
          await journalRepo.create(
            entry: build.entry,
            postings: build.postings,
          );
        } else {
          await journalRepo.replacePostings(
            id: initial.entry.id,
            entry: build.entry,
            postings: build.postings,
          );
        }
      },
    );
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showGlassModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(Spacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.expenseFormDeleteDialogTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.s8),
            Text(l10n.expenseFormDeleteDialogBody),
            const SizedBox(height: Spacing.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton.tertiary(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  label: l10n.commonCancel,
                ),
                const SizedBox(width: Spacing.s8),
                AppButton.secondary(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  label: l10n.commonDelete,
                ),
              ],
            ),
            SizedBox(height: MediaQuery.paddingOf(ctx).bottom),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final journalRepo = await ref.read(journalEntryRepositoryProvider.future);
      await journalRepo.softDelete(_initial!.entry.id);
      if (!mounted) return;
      context.go('/activity/expenses');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _amountFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loadingExisting = widget.isEdit && _initial == null;
    final allAccountsAsync = ref.watch(allAccountsStreamProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(
          widget.isEdit
              ? l10n.expenseFormEditTitle
              : l10n.expenseFormCreateTitle,
        ),
        actions: [
          if (widget.isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.expenseFormDeleteTooltip,
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: loadingExisting
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: Spacing.pageMobile,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  AmountField(
                    label: l10n.expenseFormAmountLabel,
                    controller: _amountController,
                    currencyCode: _currency,
                    focusNode: _amountFocus,
                    onFieldSubmitted: (_) => _noteFocus.requestFocus(),
                  ),
                  const SizedBox(height: Spacing.s12),
                  CurrencyPicker(
                    value: _currency,
                    onChanged: (v) => setState(() => _currency = v),
                  ),
                  const SizedBox(height: Spacing.s8),
                  allAccountsAsync.when(
                    data: (allAccounts) {
                      final expenseAccounts = allAccounts
                          .where((a) => a.category == AccountCategory.expense)
                          .toList(growable: false);
                      if (expenseAccounts.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Spacing.s12,
                          ),
                          child: Text(l10n.expenseFormCategoriesLoading),
                        );
                      }
                      // Resolve default: explicit pick > first account
                      if (_expenseAccountId == null ||
                          !expenseAccounts.any(
                            (a) => a.id == _expenseAccountId,
                          )) {
                        _expenseAccountId = expenseAccounts.first.id;
                      }
                      return CategoryGridPicker(
                        accounts: expenseAccounts,
                        selectedId: _expenseAccountId,
                        onSelect: (id) =>
                            setState(() => _expenseAccountId = id),
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: Spacing.s12),
                      child: LinearProgressIndicator(),
                    ),
                    error: (e, _) =>
                        Text(l10n.expenseFormCategoriesLoadError('$e')),
                  ),
                  const SizedBox(height: Spacing.s12),
                  accountsAsync.when(
                    data: (accounts) {
                      final fromAccounts = accounts
                          .where(
                            (a) =>
                                a.category == AccountCategory.asset &&
                                a.type != AccountType.other,
                          )
                          .toList(growable: false);
                      if (fromAccounts.isEmpty) {
                        return _NoAccountsHint();
                      }
                      final hasCurrent =
                          _fromAccountId != null &&
                          fromAccounts.any((a) => a.id == _fromAccountId);
                      if (!hasCurrent) {
                        _fromAccountId = fromAccounts.first.id;
                      }
                      return AccountPicker(
                        accounts: fromAccounts,
                        value: _fromAccountId,
                        onChanged: (v) => setState(() => _fromAccountId = v),
                        label: l10n.expenseFormAccountLabel,
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) =>
                        Text(l10n.expenseFormAccountsLoadError('$e')),
                  ),
                  const SizedBox(height: Spacing.s12),
                  DateField(
                    label: l10n.expenseFormDateLabel,
                    initialValue: _date,
                    required: true,
                    onChanged: (v) {
                      if (v != null) setState(() => _date = v);
                    },
                  ),
                  const SizedBox(height: Spacing.s12),
                  NoteField(controller: _noteController, focusNode: _noteFocus),
                  const SizedBox(height: Spacing.s24),
                  AppButton.primary(
                    onPressed: _busy ? null : _save,
                    label: _busy ? l10n.commonSaving : l10n.commonSave,
                  ),
                ],
              ),
            ),
    );
  }
}

class _NoAccountsHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LiquidGlassCard(
      layer: GlassLayer.tertiary,
      child: ListTile(
        leading: Icon(
          Icons.warning_amber_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
        title: Text(l10n.expenseFormNoAccountsTitle),
        subtitle: Text(l10n.expenseFormNoAccountsBody),
        trailing: AppButton.tertiary(
          onPressed: () => GoRouter.of(context).go('/activity/accounts/new'),
          label: l10n.expenseFormNoAccountsCta,
        ),
      ),
    );
  }
}
