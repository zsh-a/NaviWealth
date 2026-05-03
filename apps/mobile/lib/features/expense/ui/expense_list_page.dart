import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/haptics.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/expense.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'expense_category_visuals.dart';

/// User-selectable bucket size for the expense list.
enum ExpenseGrouping { month, week }

/// In-memory filter applied client-side to the materialised expense list.
class _ExpenseFilters {
  const _ExpenseFilters({
    this.fromAccountId,
    this.expenseAccountId,
    this.keyword = '',
    this.grouping = ExpenseGrouping.month,
  });

  final String? fromAccountId;
  final String? expenseAccountId;
  final String keyword;
  final ExpenseGrouping grouping;

  bool get isEmpty =>
      fromAccountId == null &&
      expenseAccountId == null &&
      keyword.trim().isEmpty;

  _ExpenseFilters copyWith({
    Object? fromAccountId = _sentinel,
    Object? expenseAccountId = _sentinel,
    String? keyword,
    ExpenseGrouping? grouping,
  }) {
    return _ExpenseFilters(
      fromAccountId: fromAccountId == _sentinel
          ? this.fromAccountId
          : fromAccountId as String?,
      expenseAccountId: expenseAccountId == _sentinel
          ? this.expenseAccountId
          : expenseAccountId as String?,
      keyword: keyword ?? this.keyword,
      grouping: grouping ?? this.grouping,
    );
  }

  static const Object _sentinel = Object();
}

class ExpenseListPage extends ConsumerStatefulWidget {
  const ExpenseListPage({super.key});

  @override
  ConsumerState<ExpenseListPage> createState() => _ExpenseListPageState();
}

class _ExpenseListPageState extends ConsumerState<ExpenseListPage> {
  _ExpenseFilters _filters = const _ExpenseFilters();
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
    final accountsAsync = ref.watch(accountsStreamProvider);

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.navExpenses),
        actions: [
          IconButton(
            tooltip: l10n.expensesReportTooltip,
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.go('/portfolio/expenses/report'),
          ),
        ],
      ),
      body: expensesAsync.when(
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
              _FiltersBar(
                accounts: accounts,
                expenseAccountById: expenseAccountById,
                filters: _filters,
                keywordController: _keywordController,
                onChanged: (f) => setState(() => _filters = f),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _Empty(filtered: !_filters.isEmpty)
                    : _GroupedList(
                        expenses: filtered,
                        expenseAccountById: expenseAccountById,
                        grouping: _filters.grouping,
                        onTap: (e) => context.go('/portfolio/expenses/${e.id}'),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
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

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.accounts,
    required this.expenseAccountById,
    required this.filters,
    required this.keywordController,
    required this.onChanged,
  });

  final List<Account> accounts;
  final Map<String, Account> expenseAccountById;
  final _ExpenseFilters filters;
  final TextEditingController keywordController;
  final ValueChanged<_ExpenseFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.s16,
        Spacing.s12,
        Spacing.s16,
        0,
      ),
      child: Column(
        children: [
          TextField(
            controller: keywordController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '按备注搜索',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: keywordController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        keywordController.clear();
                        onChanged(filters.copyWith(keyword: ''));
                      },
                    ),
            ),
            onChanged: (v) => onChanged(filters.copyWith(keyword: v)),
          ),
          const SizedBox(height: Spacing.s8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _GroupingChips(
                  selected: filters.grouping,
                  onChanged: (g) => onChanged(filters.copyWith(grouping: g)),
                ),
                const SizedBox(width: 8),
                _FilterChip<String?>(
                  label: filters.expenseAccountId == null
                      ? '全部类目'
                      : (expenseAccountById[filters.expenseAccountId]?.name ??
                            '全部类目'),
                  active: filters.expenseAccountId != null,
                  onClear: () =>
                      onChanged(filters.copyWith(expenseAccountId: null)),
                  onPick: () async {
                    final expenseAccounts = expenseAccountById.values.toList();
                    final picked = await showGlassModalBottomSheet<String?>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.clear),
                              title: const Text('全部类目'),
                              onTap: () =>
                                  Navigator.of(ctx).pop<String?>(null),
                            ),
                            for (final a in expenseAccounts)
                              ListTile(
                                leading: Icon(a.iconData),
                                title: Text(a.name),
                                onTap: () => Navigator.of(ctx).pop(a.id),
                              ),
                          ],
                        ),
                      ),
                    );
                    if (picked == null && filters.expenseAccountId == null) {
                      return;
                    }
                    onChanged(filters.copyWith(expenseAccountId: picked));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupingChips extends StatelessWidget {
  const _GroupingChips({required this.selected, required this.onChanged});

  final ExpenseGrouping selected;
  final ValueChanged<ExpenseGrouping> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ExpenseGrouping>(
      style: const ButtonStyle(
        visualDensity: VisualDensity(horizontal: -3, vertical: -3),
      ),
      segments: const [
        ButtonSegment(value: ExpenseGrouping.month, label: Text('月')),
        ButtonSegment(value: ExpenseGrouping.week, label: Text('周')),
      ],
      selected: {selected},
      onSelectionChanged: (s) {
        Haptics.selection();
        onChanged(s.first);
      },
    );
  }
}

class _FilterChip<T> extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final bool active;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      onPressed: onPick,
      avatar: active ? const Icon(Icons.check, size: 18) : null,
      onDeleted: active ? onClear : null,
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.expenses,
    required this.expenseAccountById,
    required this.grouping,
    required this.onTap,
  });

  final List<Expense> expenses;
  final Map<String, Account> expenseAccountById;
  final ExpenseGrouping grouping;
  final ValueChanged<Expense> onTap;

  @override
  Widget build(BuildContext context) {
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final groups = _groupExpenses(expenses, grouping);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s8),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final g = groups[i];
        final total = g.expenses
            .map((e) => e.amount)
            .fold<Decimal>(Decimal.zero, (a, b) => a + b);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.s16,
                Spacing.s12,
                Spacing.s16,
                Spacing.s8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(g.label, style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    '合计 ${formatter.currency(total)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFeatures: TypographyTokens.tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
            for (final e in g.expenses)
              _ExpenseRow(
                expense: e,
                account: expenseAccountById[e.expenseAccountId],
                formatter: formatter,
                onTap: () => onTap(e),
              ),
            const Divider(height: 0),
          ],
        );
      },
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.expense,
    required this.account,
    required this.formatter,
    required this.onTap,
  });

  final Expense expense;
  final Account? account;
  final AppFormatters formatter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent =
        account?.accentColor ?? Theme.of(context).colorScheme.primary;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: accent.withValues(alpha: 0.15),
        child: Icon(account?.iconData ?? Icons.payment, color: accent),
      ),
      title: Text(account?.name ?? '未分类'),
      subtitle: Text(
        [
          formatter.date(expense.tradeDate),
          if (expense.note != null && expense.note!.isNotEmpty) expense.note!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        formatter.currency(expense.amount, code: expense.currency),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontFeatures: TypographyTokens.tabularFigures,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 48),
            const SizedBox(height: Spacing.s12),
            Text(
              filtered ? '没有匹配的支出。' : '还没有记账。点底部加号按钮，开始追踪日常消费。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Group {
  _Group(this.label);

  final String label;
  final List<Expense> expenses = [];
}

List<_Group> _groupExpenses(List<Expense> expenses, ExpenseGrouping grouping) {
  final byKey = <String, _Group>{};
  for (final e in expenses) {
    final local = e.tradeDate.toLocal();
    final key = grouping == ExpenseGrouping.month
        ? '${local.year}-${local.month.toString().padLeft(2, '0')}'
        : _isoWeekKey(local);
    final label = grouping == ExpenseGrouping.month
        ? '${local.year} 年 ${local.month} 月'
        : _isoWeekLabel(local);
    byKey.putIfAbsent(key, () => _Group(label)).expenses.add(e);
  }
  final keys = byKey.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys) byKey[k]!];
}

String _isoWeekKey(DateTime d) {
  final week = _isoWeekNumber(d);
  return '${d.year}-W${week.toString().padLeft(2, '0')}';
}

String _isoWeekLabel(DateTime d) {
  final week = _isoWeekNumber(d);
  return '${d.year} 年第 $week 周';
}

int _isoWeekNumber(DateTime d) {
  final thursday = DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).add(Duration(days: 4 - d.weekday));
  final firstThursday = DateTime.utc(thursday.year, 1, 4);
  final diff = thursday.difference(firstThursday).inDays;
  return 1 + (diff / 7).floor();
}
