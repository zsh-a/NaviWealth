import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics/haptics.dart';
import '../../../data/domain/expense.dart';
import '../../../data/repositories/expense_category_repository.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import 'category_grid_picker.dart';

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

class _ExpenseFormPageState extends ConsumerState<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.expenseFormAmountInvalid)));
      return;
    }
    if (_categoryId == null || _accountId == null || _currency == null) {
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.expenseFormCategoryAccountRequired)),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = await ref.read(expenseRepositoryProvider.future);
      final note = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();
      if (_initial == null) {
        await repo.create(
          accountId: _accountId!,
          categoryId: _categoryId!,
          amount: amount,
          currency: _currency!,
          tradeDate: _date,
          note: note,
        );
      } else {
        await repo.update(
          _initial!.id,
          accountId: _accountId,
          amount: amount,
          currency: _currency,
          tradeDate: _date,
          categoryId: _categoryId,
          note: note,
          clearNote: note == null && (_initial!.note ?? '').isNotEmpty,
        );
      }
      if (!mounted) return;
      Haptics.success();
      context.go('/expenses');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loadingExisting = widget.isEdit && _initial == null;
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(expenseCategoriesStreamProvider);
    return Scaffold(
      appBar: AppBar(
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
              child: ListView(
                padding: Spacing.pageMobile,
                children: [
                  AmountField(
                    label: l10n.expenseFormAmountLabel,
                    controller: _amountController,
                    currencyCode: _currency,
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
                      // First-render default: pick the seeded "其它"
                      // bucket if it exists, else the last row in the list.
                      final fallbackId =
                          ExpenseCategoryRepository.defaultIdFor('other');
                      _categoryId ??= cats
                          .firstWhere(
                            (c) => c.id == fallbackId,
                            orElse: () => cats.last,
                          )
                          .id;
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
                      _accountId ??= accounts.first.id;
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
                  NoteField(controller: _noteController),
                  const SizedBox(height: Spacing.s24),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? l10n.commonSaving : l10n.commonSave),
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
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: ListTile(
        leading: const Icon(Icons.warning_amber_outlined),
        title: Text(l10n.expenseFormNoAccountsTitle),
        subtitle: Text(l10n.expenseFormNoAccountsBody),
        trailing: TextButton(
          onPressed: () => GoRouter.of(context).go('/accounts/new'),
          child: Text(l10n.expenseFormNoAccountsCta),
        ),
      ),
    );
  }
}
