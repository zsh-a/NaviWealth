import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/haptics.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/expense.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'expense_category_visuals.dart';
import 'expense_list_models.dart';

class ExpenseFiltersBar extends StatelessWidget {
  const ExpenseFiltersBar({
    super.key,
    required this.accounts,
    required this.expenseAccountById,
    required this.filters,
    required this.keywordController,
    required this.onChanged,
  });

  final List<Account> accounts;
  final Map<String, Account> expenseAccountById;
  final ExpenseFilters filters;
  final TextEditingController keywordController;
  final ValueChanged<ExpenseFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              hintText: l10n.expenseListSearchHint,
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
                      ? l10n.expenseListAllCategories
                      : (expenseAccountById[filters.expenseAccountId]?.name ??
                            l10n.expenseListAllCategories),
                  active: filters.expenseAccountId != null,
                  onClear: () =>
                      onChanged(filters.copyWith(expenseAccountId: null)),
                  onPick: () async {
                    final expenseAccounts = expenseAccountById.values.toList();
                    final picked = await showModalBottomSheet<String?>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.clear),
                              title: Text(l10n.expenseListAllCategories),
                              onTap: () => Navigator.of(ctx).pop<String?>(null),
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
    final l10n = AppLocalizations.of(context);
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.s4),
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final g in ExpenseGrouping.values)
            _SegmentChip(
              label: g == ExpenseGrouping.month
                  ? l10n.expenseListGroupMonth
                  : l10n.expenseListGroupWeek,
              selected: g == selected,
              onTap: () {
                Haptics.selection();
                onChanged(g);
              },
            ),
        ],
      ),
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.s12,
          vertical: Spacing.s6,
        ),
        decoration: selected
            ? BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Radii.md),
              )
            : null,
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
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

class ExpenseGroupedList extends StatelessWidget {
  const ExpenseGroupedList({
    super.key,
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
    final l10n = AppLocalizations.of(context);
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final groups = _groupExpenses(expenses, grouping, l10n);
    final items = <_ExpenseListItem>[];
    for (final group in groups) {
      items.add(_ExpenseGroupHeader(group));
      for (final expense in group.expenses) {
        items.add(_ExpenseListRow(expense));
      }
      items.add(const _ExpenseListDivider());
    }

    return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.s8),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return switch (item) {
            _ExpenseGroupHeader(:final group) => Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.s16,
                Spacing.s12,
                Spacing.s16,
                Spacing.s8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    group.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    l10n.expenseListTotal(formatter.currency(group.total)),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFeatures: TypographyTokens.tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
            _ExpenseListRow(:final expense) => _ExpenseRow(
              expense: expense,
              account: expenseAccountById[expense.expenseAccountId],
              formatter: formatter,
              onTap: () => onTap(expense),
            ),
            _ExpenseListDivider() => const Divider(height: 0),
          };
        },
      );
  }
}

sealed class _ExpenseListItem {
  const _ExpenseListItem();
}

class _ExpenseGroupHeader extends _ExpenseListItem {
  const _ExpenseGroupHeader(this.group);

  final _Group group;
}

class _ExpenseListRow extends _ExpenseListItem {
  const _ExpenseListRow(this.expense);

  final Expense expense;
}

class _ExpenseListDivider extends _ExpenseListItem {
  const _ExpenseListDivider();
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
    final l10n = AppLocalizations.of(context);
    final accent =
        account?.accentColor ?? Theme.of(context).colorScheme.primary;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: accent.withValues(alpha: 0.15),
        child: Icon(account?.iconData ?? Icons.payment, color: accent),
      ),
      title: Text(account?.name ?? l10n.expenseListUncategorized),
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

class EmptyExpenseList extends StatelessWidget {
  const EmptyExpenseList({super.key, required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 48),
            const SizedBox(height: Spacing.s12),
            Text(
              filtered
                  ? l10n.expenseListEmptyFiltered
                  : l10n.expenseListEmptyDefault,
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

  Decimal get total =>
      expenses.fold<Decimal>(Decimal.zero, (total, e) => total + e.amount);
}

List<_Group> _groupExpenses(
  List<Expense> expenses,
  ExpenseGrouping grouping,
  AppLocalizations l10n,
) {
  final byKey = <String, _Group>{};
  for (final e in expenses) {
    final local = e.tradeDate.toLocal();
    final key = grouping == ExpenseGrouping.month
        ? '${local.year}-${local.month.toString().padLeft(2, '0')}'
        : _isoWeekKey(local);
    final label = grouping == ExpenseGrouping.month
        ? l10n.expenseListMonthGroup(local.year, local.month)
        : _isoWeekLabel(local, l10n);
    byKey.putIfAbsent(key, () => _Group(label)).expenses.add(e);
  }
  final keys = byKey.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys) byKey[k]!];
}

String _isoWeekKey(DateTime d) {
  final week = _isoWeekNumber(d);
  return '${d.year}-W${week.toString().padLeft(2, '0')}';
}

String _isoWeekLabel(DateTime d, AppLocalizations l10n) {
  final week = _isoWeekNumber(d);
  return l10n.expenseListWeekGroup(d.year, week);
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
