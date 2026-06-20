import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../core/format/formatters.dart';
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
    final accountsAsync = ref.watch(allAccountsStreamProvider);
    final allAccounts = accountsAsync.value ?? const <Account>[];
    final expenseAccountById = {
      for (final a in allAccounts.where(
        (a) => a.category == AccountSide.expense,
      ))
        a.id: a,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s8,
        AppSpacing.s12,
        AppSpacing.s24,
      ),
      children: [
        const _RangeChips(),
        const SizedBox(height: AppSpacing.s12),
        _SummaryCard(report: report),
        const SizedBox(height: AppSpacing.s12),
        ExpenseCategoryPieCard(
          report: report,
          categoryById: expenseAccountById,
        ),
        const SizedBox(height: AppSpacing.s12),
        ExpenseTrendCard(report: report),
        const SizedBox(height: AppSpacing.s12),
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
    return SegmentedRow<ExpenseReportRangePreset>(
      options: ExpenseReportRangePreset.values,
      value: selected,
      labelOf: (preset) => _label(preset, l10n),
      onChanged: (preset) => _select(context, ref, preset),
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
      final picked = await showAppFormSheet<({DateTime from, DateTime to})>(
        context: context,
        maxHeightFactor: 0.82,
        builder: (_) => _ExpenseReportRangeSheet(
          initialFrom: initial.from,
          initialTo: initial.to,
          firstDate: DateTime(now.year - 5),
          lastDate: now,
        ),
      );
      if (picked == null) return;
      ref.read(expenseReportCustomRangeProvider.notifier).state = (
        from: picked.from,
        to: picked.to,
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

class _ExpenseReportRangeSheet extends StatefulWidget {
  const _ExpenseReportRangeSheet({
    required this.initialFrom,
    required this.initialTo,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialFrom;
  final DateTime initialTo;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_ExpenseReportRangeSheet> createState() =>
      _ExpenseReportRangeSheetState();
}

class _ExpenseReportRangeSheetState extends State<_ExpenseReportRangeSheet> {
  late final FCalendarController<(DateTime, DateTime)?> _controller;

  @override
  void initState() {
    super.initState();
    _controller = FCalendarController.range(
      initial: (_utcDay(widget.initialFrom), _utcDay(widget.initialTo)),
      selectable: (date) {
        final day = _utcDay(date);
        return !day.isBefore(_utcDay(widget.firstDate)) &&
            !day.isAfter(_utcDay(widget.lastDate));
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    return ValueListenableBuilder<(DateTime, DateTime)?>(
      valueListenable: _controller,
      builder: (context, selected, _) {
        return AppSheet(
          title: l10n.expenseReportRangeCustom,
          subtitle: selected == null
              ? null
              : '${formatter.date(selected.$1)} - ${formatter.date(selected.$2)}',
          footer: Row(
            children: [
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => Navigator.of(context).maybePop(),
                  child: Text(l10n.commonCancel),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: FButton(
                  onPress: selected == null
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop((from: selected.$1, to: selected.$2)),
                  child: Text(l10n.commonConfirm),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.muted.withValues(alpha: AppOpacity.subtle),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: colors.foreground.withValues(
                      alpha: AppOpacity.whisper,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s8),
                  child: Center(
                    child: FCalendar(
                      control: FCalendarControl.managedRange(
                        controller: _controller,
                      ),
                      start: _utcDay(widget.firstDate),
                      end: _utcDay(
                        widget.lastDate.add(const Duration(days: 1)),
                      ),
                      today: _utcDay(DateTime.now()),
                      initialMonth: _utcDay(widget.initialTo),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

DateTime _utcDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final ExpenseReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final monthSpan = report.range.monthSpan;
    final divisor = Decimal.fromInt(monthSpan == 0 ? 1 : monthSpan);
    final avgDecimal = (report.total.amount / divisor).toDecimal(
      scaleOnInfinitePrecision: 2,
    );
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.expenseReportTotalExpenses,
              style: context.theme.typography.sm,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              formatter.currency(
                report.total.amount,
                code: report.baseCurrency,
              ),
              style: context.theme.typography.xl.copyWith(
                fontFeatures: TypographyTokens.tabularFigures,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
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
              const SizedBox(height: AppSpacing.s8),
              Text(
                l10n.expenseReportSkippedFx(report.skippedFxCount),
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.destructive,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.expenseReportBaseCurrency(report.baseCurrency, monthSpan),
              style: context.captionStyle,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.captionStyle,
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.theme.typography.md.copyWith(
            fontFeatures: TypographyTokens.tabularFigures,
          ),
        ),
      ],
    );
  }
}
