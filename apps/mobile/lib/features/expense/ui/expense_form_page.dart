import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics/haptics.dart';
import '../../../data/domain/expense.dart';
import '../../../data/repositories/expense_category_repository.dart';
import '../../../data/repositories/journal_entry_builders.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/mutation_context.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import '../data/expense_account_resolver.dart';
import '../data/recent_expense_categories.dart';
import 'category_grid_picker.dart';
import 'expense_history_timeline.dart';

/// Quick-entry page for a single expense. Shared between create and edit
/// flows — when [expenseId] is non-null we hydrate the form from the
/// repository and call `update`; otherwise we call `recordExpense`.
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

  // amount → note. Note's keyboard action stays as `newline`, so we don't
  // chain past it; the user submits via the FilledButton or by hitting
  // done from the amount field when no note is desired.
  final _amountFocus = FocusNode();
  final _noteFocus = FocusNode();

  String? _categoryId;
  String? _accountId;
  String? _currency = 'CNY';
  DateTime _date = DateTime.now();
  bool _busy = false;
  Expense? _initial;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) {
      _loadInitial();
    } else {
      // Smart defaults from last entry. Concrete account / category may be
      // re-validated against the live lists below; this is just the
      // initial seed.
      final defaults = ref.read(formDefaultsProvider);
      _accountId = defaults.expenseAccountId;
      _categoryId = defaults.expenseCategoryId;
      if (defaults.expenseCurrency != null &&
          defaults.expenseCurrency!.isNotEmpty) {
        _currency = defaults.expenseCurrency;
      }
    }
  }

  Future<void> _loadInitial() async {
    final repo = await ref.read(expenseRepositoryProvider.future);
    final existing = await repo.findById(widget.expenseId!);
    if (existing == null || !mounted) return;
    setState(() {
      _initial = existing;
      _amountController.text = existing.amount.toString();
      _noteController.text = existing.note ?? '';
      _categoryId = existing.categoryId;
      _accountId = existing.accountId;
      _currency = existing.currency;
      _date = existing.tradeDate;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final amount = readAmount(_amountController);
    if (amount == null || amount <= Decimal.zero) {
      Haptics.error();
      AppMessenger.show(context, ToastKind.error, l10n.expenseFormAmountInvalid);
      return;
    }
    if (_categoryId == null || _accountId == null || _currency == null) {
      Haptics.error();
      AppMessenger.show(context, ToastKind.error, l10n.expenseFormCategoryAccountRequired);
      return;
    }
    setState(() => _busy = true);
    final repo = await ref.read(expenseRepositoryProvider.future);
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    final accountId = _accountId!;
    final categoryId = _categoryId!;
    final currency = _currency!;
    final date = _date;
    final initial = _initial;
    if (!mounted) return;
    // Persist last-used picks so the next entry skips category/account
    // tapping. Fire-and-forget: it's a SharedPreferences write that doesn't
    // gate the user-visible flow, and the user has already committed by
    // tapping save.
    unawaited(
      ref.read(formDefaultsProvider.notifier).rememberExpense(
            accountId: accountId,
            categoryId: categoryId,
            currency: currency,
          ),
    );
    await submitOptimistic(
      pop: () {
        // Fire the success haptic at pop time — the user feels confirmation
        // the moment the form closes, even though the write is still
        // in flight. Failure replays via Haptics.error() inside the
        // OptimisticFormSubmit failure path.
        Haptics.success();
        context.go('/expenses');
      },
      tag: 'expense',
      failureMessage: (_) => l10n.commonSaveFailed,
      retryLabel: l10n.commonRetry,
      write: () async {
        if (initial == null) {
          // FIR-131 wave 3f — new expenses go through the journal-
          // entry stack. The legacy `expense_categories` taxonomy is
          // still the picker the user sees, so we translate
          // `categoryId` to a FIR-133 expense account on the way
          // through. Edit / delete flows below stay on the legacy
          // repo until FIR-132 retires the read path.
          final ownerUserId =
              await ref.read(currentUserIdProvider).call();
          final expenseAccountId =
              LegacyExpenseCategoryToAccount.resolveAccountId(
            categoryId: categoryId,
            ownerUserId: ownerUserId,
          );
          final journalRepo =
              await ref.read(journalEntryRepositoryProvider.future);
          final build = JournalEntryBuilders.expense(
            date: date,
            expenseAccountId: expenseAccountId,
            fromAccountId: accountId,
            amount: amount,
            currency: currency,
            // The builder defaults narration to 'Expense' when null;
            // the user's free-text note (when present) is the more
            // useful headline in JournalEntryListPage.
            narration: note,
          );
          await journalRepo.create(
            entry: build.entry,
            postings: build.postings,
          );
        } else {
          await repo.update(
            initial.id,
            accountId: accountId,
            amount: amount,
            currency: currency,
            tradeDate: date,
            categoryId: categoryId,
            note: note,
            clearNote: note == null && (initial.note ?? '').isNotEmpty,
          );
        }
      },
    );
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.expenseFormDeleteDialogTitle),
        content: Text(l10n.expenseFormDeleteDialogBody),
        actions: [
          AppButton.tertiary(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: l10n.commonCancel,
          ),
          AppButton.secondary(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: l10n.commonDelete,
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(expenseRepositoryProvider.future);
      await repo.softDelete(_initial!.id);
      if (!mounted) return;
      context.go('/expenses');
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
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(expenseCategoriesStreamProvider);
    final mostUsedCategoryId = ref.watch(mostUsedExpenseCategoryProvider);
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
                  categoriesAsync.when(
                    data: (cats) {
                      if (cats.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Spacing.s12,
                          ),
                          child: Text(l10n.expenseFormCategoriesLoading),
                        );
                      }
                      // Picker only fires the default fallback if the
                      // user hasn't already chosen something — including
                      // the persisted last-used pick from initState. The
                      // ranking goes: explicit pick > last used > recent
                      // most-used > seeded "其它" > final list row.
                      final fallbackId =
                          ExpenseCategoryRepository.defaultIdFor('other');
                      final candidates = <String?>[
                        _categoryId,
                        mostUsedCategoryId,
                      ];
                      String? resolved;
                      for (final candidate in candidates) {
                        if (candidate != null &&
                            cats.any((c) => c.id == candidate)) {
                          resolved = candidate;
                          break;
                        }
                      }
                      resolved ??= cats
                          .firstWhere(
                            (c) => c.id == fallbackId,
                            orElse: () => cats.last,
                          )
                          .id;
                      _categoryId = resolved;
                      return CategoryGridPicker(
                        categories: cats,
                        selectedId: _categoryId,
                        onSelect: (id) => setState(() => _categoryId = id),
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
                      if (accounts.isEmpty) {
                        return _NoAccountsHint();
                      }
                      // Drop a stale persisted account if it no longer
                      // exists; otherwise honour the user's pick over the
                      // first-row default.
                      final hasCurrent = _accountId != null &&
                          accounts.any((a) => a.id == _accountId);
                      if (!hasCurrent) {
                        _accountId = accounts.first.id;
                      }
                      return AccountPicker(
                        accounts: accounts,
                        value: _accountId,
                        onChanged: (v) => setState(() => _accountId = v),
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
                  NoteField(
                    controller: _noteController,
                    focusNode: _noteFocus,
                  ),
                  const SizedBox(height: Spacing.s24),
                  AppButton.primary(
                    onPressed: _busy ? null : _save,
                    label: _busy ? l10n.commonSaving : l10n.commonSave,
                  ),
                  if (widget.isEdit && _initial != null) ...[
                    const SizedBox(height: Spacing.s24),
                    ExpenseHistoryTimeline(expenseId: _initial!.id),
                  ],
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
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: ListTile(
        leading: const Icon(Icons.warning_amber_outlined),
        title: Text(l10n.expenseFormNoAccountsTitle),
        subtitle: Text(l10n.expenseFormNoAccountsBody),
        trailing: AppButton.tertiary(
          onPressed: () => GoRouter.of(context).go('/accounts/new'),
          label: l10n.expenseFormNoAccountsCta,
        ),
      ),
    );
  }
}
