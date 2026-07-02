import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/composition/ask_ai.dart';
import 'package:naviwealth/core/ai/intent/intent.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'expense_list_content.dart';
import 'expense_list_models.dart';

class ExpenseListPage extends ConsumerStatefulWidget {
  const ExpenseListPage({super.key});

  @override
  ConsumerState<ExpenseListPage> createState() => _ExpenseListPageState();
}

class _ExpenseListPageState extends ConsumerState<ExpenseListPage> {
  ExpenseFilters _filters = const ExpenseFilters();
  final _keywordController = TextEditingController();
  Timer? _keywordDebounce;
  String _appliedKeyword = '';
  final Set<String> _selectedExpenseIds = <String>{};

  @override
  void dispose() {
    _keywordDebounce?.cancel();
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expensesAsync = ref.watch(journalExpensesStreamProvider);
    final accountsAsync = ref.watch(allAccountsStreamProvider);

    final body = expensesAsync.whenOrLoading(
      data: (all) {
        final accounts = accountsAsync.value ?? const <Account>[];
        final expenseAccountById = {
          for (final a in accounts.where(
            (a) => a.category == AccountSide.expense,
          ))
            a.id: a,
        };
        final filtered = _applyFilters(all);
        final selectedVisible = filtered
            .where((expense) => _selectedExpenseIds.contains(expense.id))
            .toList(growable: false);
        return Column(
          children: [
            ExpenseFiltersBar(
              accounts: accounts,
              expenseAccountById: expenseAccountById,
              filters: _filters,
              keywordController: _keywordController,
              onChanged: _onFiltersChanged,
            ),
            if (selectedVisible.isNotEmpty)
              ExpenseSelectionToolbar(
                selectedCount: selectedVisible.length,
                onExplain: () => _explainSelection(selectedVisible),
                onClear: _clearSelection,
              ),
            Expanded(
              child: filtered.isEmpty
                  ? EmptyExpenseList(filtered: !_filters.isEmpty)
                  : ExpenseGroupedList(
                      expenses: filtered,
                      expenseAccountById: expenseAccountById,
                      grouping: _filters.grouping,
                      onTap: (e) => context.push(FinanceRoutes.expense(e.id)),
                      selectedExpenseIds: _selectedExpenseIds,
                      onToggleSelected: _toggleSelected,
                    ),
            ),
          ],
        );
      },
      error: (e, _) => AppEmptyState.error(
        title: l10n.commonLoadFailed,
        message: l10n.commonLoadError('$e'),
        action: FButton(
          variant: FButtonVariant.ghost,
          onPress: () {
            ref.invalidate(journalExpensesStreamProvider);
            ref.invalidate(allAccountsStreamProvider);
          },
          child: Text(l10n.commonRetry),
        ),
      ),
    );

    return AppPageScaffold(
      title: l10n.navExpenses,
      childPad: false,
      child: body,
    );
  }

  void _onFiltersChanged(ExpenseFilters updated) {
    final keywordChanged = updated.keyword != _filters.keyword;
    // Always update _filters so the text controller / clear button stay in sync.
    setState(() {
      _filters = updated;
      _selectedExpenseIds.clear();
    });
    if (keywordChanged && updated.keyword.isNotEmpty) {
      // Typing: debounce the actual filter to avoid rebuilding on every keystroke.
      _keywordDebounce?.cancel();
      _keywordDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() => _appliedKeyword = updated.keyword.trim().toLowerCase());
      });
    } else {
      // Clearing or non-keyword changes apply immediately.
      _keywordDebounce?.cancel();
      _appliedKeyword = updated.keyword.trim().toLowerCase();
    }
  }

  void _toggleSelected(Expense expense) {
    setState(() {
      if (!_selectedExpenseIds.add(expense.id)) {
        _selectedExpenseIds.remove(expense.id);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedExpenseIds.clear);
  }

  Future<void> _explainSelection(List<Expense> selected) async {
    if (selected.isEmpty) return;
    final ids = [for (final expense in selected) expense.id];
    await askAi(
      context,
      ref,
      intent: 'transactions.explainSelection',
      object: AiObjectRef(type: 'transactions', id: ids.join(',')),
      objectLabel: AppLocalizations.of(
        context,
      ).expenseListSelectedCount(selected.length),
      source: 'expense_list_selection',
      attrs: <String, Object?>{
        'transaction_ids': ids,
        'count': selected.length,
      },
      capabilities: const <AiCapability>{
        AiCapability.chat,
        AiCapability.visualization,
      },
    );
    if (!mounted) return;
    _clearSelection();
  }

  List<Expense> _applyFilters(List<Expense> all) {
    final keyword = _appliedKeyword;
    return all.where((e) {
      if (_filters.fromAccountId != null &&
          _filters.fromAccountId!.isNotEmpty) {
        if (e.fromAccountId != _filters.fromAccountId) return false;
      }
      if (_filters.expenseAccountId != null &&
          e.expenseAccountId != _filters.expenseAccountId) {
        return false;
      }
      if (keyword.isEmpty) return true;
      final note = (e.note ?? '').toLowerCase();
      return note.contains(keyword);
    }).toList();
  }
}
