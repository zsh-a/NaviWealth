import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/expense_report_providers.dart';
import '../domain/expense_report.dart';
import '../domain/expense_report_range.dart';
import 'expense_report_sections.dart';

class ExpenseReportBody extends ConsumerWidget {
  const ExpenseReportBody({super.key, required this.report});

  final ExpenseReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final allAccounts = accountsAsync.value ?? const <Account>[];
    final expenseAccountById = {
      for (final a in allAccounts.where(
        (a) => a.category == AccountCategory.expense,
      ))
        a.id: a,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Spacing.s12,
        Spacing.s8,
        Spacing.s12,
        Spacing.s24,
      ),
      children: [
        const _RangeChips(),
        const SizedBox(height: Spacing.s12),
        _SummaryCard(report: report),
        const SizedBox(height: Spacing.s12),
        ExpenseCategoryPieCard(
          report: report,
          categoryById: expenseAccountById,
        ),
        const SizedBox(height: Spacing.s12),
        ExpenseTrendCard(report: report),
        const SizedBox(height: Spacing.s12),
        ExpenseCategoryListCard(
          report: report,
          categoryById: expenseAccountById,
        ),
      ],
    );
  }
}

class _RangeChips extends ConsumerWidget {
  const _RangeChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(expenseReportRangePresetProvider);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final preset in ExpenseReportRangePreset.values)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.s8),
              child: FButton(
                variant: (preset == selected)
                    ? FButtonVariant.primary
                    : FButtonVariant.outline,
                onPress: () => _select(context, ref, preset),
                child: Text(_label(preset, l10n)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    ExpenseReportRangePreset preset,
  ) async {
    if (preset == ExpenseReportRangePreset.custom) {
      final now = DateTime.now();
      final initial =
          ref.read(expenseReportCustomRangeProvider) ??
          (from: DateTime(now.year, now.month - 2, 1), to: now);
      final picked = await showDateRangePicker(
        context: context,
        initialDateRange: DateTimeRange(start: initial.from, end: initial.to),
        firstDate: DateTime(now.year - 5),
        lastDate: now,
      );
      if (picked == null) return;
      ref.read(expenseReportCustomRangeProvider.notifier).state = (
        from: picked.start,
        to: picked.end,
      );
      ref.read(expenseReportRangePresetProvider.notifier).state = preset;
      return;
    }
    ref.read(expenseReportCustomRangeProvider.notifier).state = null;
    ref.read(expenseReportRangePresetProvider.notifier).state = preset;
  }

  String _label(ExpenseReportRangePreset preset, AppLocalizations l10n) {
    switch (preset) {
      case ExpenseReportRangePreset.monthToDate:
        return l10n.expenseReportRangeThisMonth;
      case ExpenseReportRangePreset.m3:
        return l10n.expenseReportRangeLast3Months;
      case ExpenseReportRangePreset.m6:
        return l10n.expenseReportRangeLast6Months;
      case ExpenseReportRangePreset.m12:
        return l10n.expenseReportRangeLast12Months;
      case ExpenseReportRangePreset.custom:
        return l10n.expenseReportRangeCustom;
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final ExpenseReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final monthSpan = report.range.monthSpan;
    final divisor = Decimal.fromInt(monthSpan == 0 ? 1 : monthSpan);
    final avgDecimal = (report.total.amount / divisor).toDecimal(
      scaleOnInfinitePrecision: 2,
    );
    return FCard.raw(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.expenseReportTotalExpenses,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              formatter.currency(
                report.total.amount,
                code: report.baseCurrency,
              ),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: TypographyTokens.tabularFigures,
              ),
            ),
            const SizedBox(height: Spacing.s8),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: l10n.expenseReportMonthlyAverage,
                    value: formatter.compactCurrency(
                      avgDecimal,
                      code: report.baseCurrency,
                    ),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: l10n.expenseReportEntryCount,
                    value: report.byCategory
                        .fold<int>(0, (a, c) => a + c.items.length)
                        .toString(),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: l10n.expenseReportCategoryCount,
                    value: report.byCategory.length.toString(),
                  ),
                ),
              ],
            ),
            if (report.skippedFxCount > 0) ...[
              const SizedBox(height: Spacing.s8),
              Text(
                l10n.expenseReportSkippedFx(report.skippedFxCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: Spacing.s4),
            Text(
              l10n.expenseReportBaseCurrency(report.baseCurrency, monthSpan),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: TypographyTokens.tabularFigures,
          ),
        ),
      ],
    );
  }
}
