import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/domain/expense.dart';
import '../../../data/repositories/expense_category_repository.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
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
    final amount = readAmount(_amountController);
    if (amount == null || amount <= Decimal.zero) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('金额必须大于 0')));
      return;
    }
    if (_categoryId == null || _accountId == null || _currency == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择类目、账户和币种')));
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
      context.go('/expenses');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除支出'),
        content: const Text('确认删除此支出？该操作可同步给其他设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
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
    final loadingExisting = widget.isEdit && _initial == null;
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(expenseCategoriesStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? '编辑支出' : '新建支出'),
        actions: [
          if (widget.isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
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
                    label: '金额',
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
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: Spacing.s12),
                          child: Text('正在准备默认类目，请稍候…'),
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
                    error: (e, _) => Text('类目加载失败：$e'),
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
                        label: '账户',
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('账户加载失败：$e'),
                  ),
                  const SizedBox(height: Spacing.s12),
                  DateField(
                    label: '日期',
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
                    child: Text(_busy ? '保存中…' : '保存'),
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
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: ListTile(
        leading: const Icon(Icons.warning_amber_outlined),
        title: const Text('先创建一个账户'),
        subtitle: const Text('支出需要选择资金账户。前往「账户」新建后再来录入。'),
        trailing: TextButton(
          onPressed: () => GoRouter.of(context).go('/accounts/new'),
          child: const Text('去创建'),
        ),
      ),
    );
  }
}
