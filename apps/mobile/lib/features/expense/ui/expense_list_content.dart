import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/account_l10n.dart';
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
    final categoryLabelById = {
      for (final entry in expenseAccountById.entries)
        entry.key: localizedAccountPath(l10n, entry.value, expenseAccountById),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        0,
      ),
      child: Column(
        children: [
          FTextField(
            control: FTextFieldControl.managed(
              controller: keywordController,
              onChange: (v) => onChanged(filters.copyWith(keyword: v.text)),
            ),
            hint: l10n.expenseListSearchHint,
            prefixBuilder: (ctx, style, variants) => const Padding(
              padding: EdgeInsetsDirectional.only(
                start: AppSpacing.s12,
                end: AppSpacing.s8,
              ),
              child: Icon(FLucideIcons.search, size: AppIconSizes.h18),
            ),
            suffixBuilder: keywordController.text.isEmpty
                ? null
                : (ctx, style, variants) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: FButton.icon(
                      variant: FButtonVariant.ghost,
                      onPress: () {
                        keywordController.clear();
                        onChanged(filters.copyWith(keyword: ''));
                      },
                      child: const Icon(FLucideIcons.x, size: AppIconSizes.h18),
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.s8),
          SizedBox(
            height: AppControlHeights.compactChipRail,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _GroupingChips(
                  selected: filters.grouping,
                  onChanged: (g) => onChanged(filters.copyWith(grouping: g)),
                ),
                const SizedBox(width: AppSpacing.s8),
                _FilterChip<String?>(
                  label: filters.expenseAccountId == null
                      ? l10n.expenseListAllCategories
                      : (categoryLabelById[filters.expenseAccountId] ??
                            l10n.expenseListAllCategories),
                  active: filters.expenseAccountId != null,
                  onClear: () =>
                      onChanged(filters.copyWith(expenseAccountId: null)),
                  onPick: () async {
                    final expenseAccounts = expenseAccountById.values.toList();
                    final picked = await showAppSheet<String?>(
                      context: context,
                      title: l10n.expenseListAllCategories,
                      builder: (ctx) => ListView(
                        shrinkWrap: true,
                        children: [
                          FTile(
                            title: Text(l10n.expenseListAllCategories),
                            prefix: const Icon(FLucideIcons.x),
                            onPress: () => Navigator.of(ctx).pop<String?>(null),
                          ),
                          for (final a in expenseAccounts)
                            FTile(
                              title: Text(
                                categoryLabelById[a.id] ??
                                    localizedAccountName(l10n, a),
                              ),
                              prefix: Icon(a.iconData),
                              onPress: () => Navigator.of(ctx).pop(a.id),
                            ),
                        ],
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
    return SegmentedRow<ExpenseGrouping>(
      options: ExpenseGrouping.values,
      value: selected,
      labelOf: (g) => g == ExpenseGrouping.month
          ? l10n.expenseListGroupMonth
          : l10n.expenseListGroupWeek,
      onChanged: (g) {
        Haptics.selection();
        onChanged(g);
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
    return AppFilterChip(
      label: label,
      active: active,
      onPress: onPick,
      onClear: active ? onClear : null,
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
    this.selectedExpenseIds = const <String>{},
    this.onToggleSelected,
  });

  final List<Expense> expenses;
  final Map<String, Account> expenseAccountById;
  final ExpenseGrouping grouping;
  final ValueChanged<Expense> onTap;
  final Set<String> selectedExpenseIds;
  final ValueChanged<Expense>? onToggleSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final groups = _groupExpenses(expenses, grouping, l10n);
    final items = <_ExpenseListItem>[];
    for (final group in groups) {
      items.add(_ExpenseGroupHeader(group));
      for (var i = 0; i < group.expenses.length; i++) {
        items.add(
          _ExpenseListRow(
            expense: group.expenses[i],
            showDivider: i < group.expenses.length - 1,
          ),
        );
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return switch (item) {
          _ExpenseGroupHeader(:final group) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s12,
              AppSpacing.s16,
              AppSpacing.s8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.label,
                    style: context.theme.typography.body.sm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: MoneyText(
                    amount: group.total.toDouble(),
                    compact: true,
                    style: context.bodyCaptionStyle,
                  ),
                ),
              ],
            ),
          ),
          _ExpenseListRow(:final expense, :final showDivider) => _ExpenseRow(
            expense: expense,
            account: expenseAccountById[expense.expenseAccountId],
            formatter: formatter,
            onTap: () => onTap(expense),
            selected: selectedExpenseIds.contains(expense.id),
            onToggleSelected: onToggleSelected == null
                ? null
                : () => onToggleSelected!(expense),
            showDivider: showDivider,
          ),
        };
      },
    );
  }
}

class ExpenseSelectionToolbar extends StatelessWidget {
  const ExpenseSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.onExplain,
    required this.onClear,
  });

  final int selectedCount;
  final VoidCallback onExplain;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        0,
      ),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.expenseListSelectedCount(selectedCount),
              style: context.labelStyle,
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s6,
              runSpacing: AppSpacing.s6,
              children: [
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: onClear,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FLucideIcons.x, size: AppIconSizes.h18),
                      const SizedBox(width: AppSpacing.s4),
                      Text(l10n.expenseListClearSelection),
                    ],
                  ),
                ),
                FButton(
                  onPress: onExplain,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FLucideIcons.sparkles, size: AppIconSizes.h18),
                      const SizedBox(width: AppSpacing.s4),
                      Text(l10n.expenseListExplainSelected),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
  const _ExpenseListRow({required this.expense, required this.showDivider});

  final Expense expense;
  final bool showDivider;
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.expense,
    required this.account,
    required this.formatter,
    required this.onTap,
    required this.selected,
    required this.onToggleSelected,
    required this.showDivider,
  });

  final Expense expense;
  final Account? account;
  final AppFormatters formatter;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback? onToggleSelected;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accent =
        account?.expenseAccentColor(context) ?? context.theme.colors.primary;
    final title = account == null
        ? l10n.expenseListUncategorized
        : localizedAccountName(l10n, account!);
    final subtitle = [
      formatter.date(expense.tradeDate),
      if (expense.note != null && expense.note!.isNotEmpty) expense.note!,
    ].join(' · ');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s10,
          ),
          child: Row(
            children: [
              if (onToggleSelected != null) ...[
                SizedBox(
                  width: AppSpacing.s32,
                  child: FCheckbox(
                    value: selected,
                    onChange: (_) => onToggleSelected!(),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
              ],
              Expanded(
                child: FTappable(
                  onPress: onTap,
                  child: Row(
                    children: [
                      SizedBox(
                        width: AppSpacing.s32,
                        height: AppSpacing.s32,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Icon(
                            account?.iconData ?? FLucideIcons.banknote,
                            size: AppIconSizes.md,
                            color: accent.withValues(
                              alpha: AppOpacity.prominent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: context.labelStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              subtitle,
                              style: context.captionStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      MoneyText(
                        amount: expense.amount.toDouble(),
                        currencyCode: expense.currency,
                        style: context.strongLabelStyle,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpacing.s64),
            child: SizedBox(
              height: AppSpacing.hairline,
              child: ColoredBox(
                color: context.theme.colors.border.withValues(
                  alpha: AppOpacity.faint,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class EmptyExpenseList extends StatelessWidget {
  const EmptyExpenseList({super.key, required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.receipt,
      title: filtered
          ? l10n.expenseListEmptyFiltered
          : l10n.expenseListEmptyDefault,
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
