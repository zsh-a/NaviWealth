import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../app/route_paths.dart';
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
  Timer? _keywordDebounce;
  String _appliedKeyword = '';

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

    final body = expensesAsync.when(
      data: (all) {
        final accounts = accountsAsync.value ?? const <Account>[];
        final expenseAccountById = {
          for (final a in accounts.where(
            (a) => a.category == AccountSide.expense,
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
              onChanged: _onFiltersChanged,
            ),
            Expanded(
              child: filtered.isEmpty
                  ? EmptyExpenseList(filtered: !_filters.isEmpty)
                  : ExpenseGroupedList(
                      expenses: filtered,
                      expenseAccountById: expenseAccountById,
                      grouping: _filters.grouping,
                      onTap: (e) => context.push(AppRoutes.expense(e.id)),
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => Center(child: Text(l10n.commonLoadError('$e'))),
    );

    if (widget.embedded) return body;
    return AppPageScaffold(
      title: l10n.navExpenses,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.lightbulb),
          onPress: () => context.push(AppRoutes.expenseReport),
        ),
      ],
      childPad: false,
      child: body,
    );
  }

  void _onFiltersChanged(ExpenseFilters updated) {
    final keywordChanged = updated.keyword != _filters.keyword;
    // Always update _filters so the text controller / clear button stay in sync.
    setState(() => _filters = updated);
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
