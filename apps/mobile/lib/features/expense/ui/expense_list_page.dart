import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/expense.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'expense_list_content.dart';
import 'expense_list_models.dart';

class ExpenseListPage extends ConsumerStatefulWidget {
  const ExpenseListPage({super.key, this.embedded = false});

  /// When true, skips the Scaffold/AppBar so the page can be embedded
  /// inside another Scaffold (e.g., the Activity tab).
  final bool embedded;

  @override
  ConsumerState<ExpenseListPage> createState() => _ExpenseListPageState();
}

class _ExpenseListPageState extends ConsumerState<ExpenseListPage> {
  ExpenseFilters _filters = const ExpenseFilters();
  final _keywordController = TextEditingController();

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expensesAsync = ref.watch(journalExpensesStreamProvider);
    final accountsAsync = ref.watch(allAccountsStreamProvider);

    final body = expensesAsync.when(
      data: (all) {
        final accounts = accountsAsync.value ?? const <Account>[];
        final expenseAccountById = {
          for (final a in accounts.where(
            (a) => a.category == AccountCategory.expense,
          ))
            a.id: a,
        };
        final filtered = _applyFilters(all);
        return Column(
          children: [
            ExpenseFiltersBar(
              accounts: accounts,
              expenseAccountById: expenseAccountById,
              filters: _filters,
              keywordController: _keywordController,
              onChanged: (f) => setState(() => _filters = f),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? EmptyExpenseList(filtered: !_filters.isEmpty)
                  : ExpenseGroupedList(
                      expenses: filtered,
                      expenseAccountById: expenseAccountById,
                      grouping: _filters.grouping,
                      onTap: (e) => context.go(AppRoutes.expense(e.id)),
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l10n.commonLoadError('$e'))),
    );

    if (widget.embedded) return body;
    return PageScaffold(
      appBar: GlassAppBar(
        title: Text(l10n.navExpenses),
        actions: [
          IconButton(
            tooltip: l10n.expensesReportTooltip,
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.go(AppRoutes.expenseReport),
          ),
        ],
      ),
      padding: EdgeInsets.zero,
      body: body,
    );
  }

  List<Expense> _applyFilters(List<Expense> all) {
    final keyword = _filters.keyword.trim().toLowerCase();
    return all.where((e) {
      if (_filters.fromAccountId != null &&
          _filters.fromAccountId!.isNotEmpty) {
        // fromAccountId is not on the Expense model; skip this filter
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
