import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/cash_flow_providers.dart';
import '../data/recurring_transaction_providers.dart';
import '../domain/cash_flow_aggregator.dart';
import '../domain/cash_flow_kind.dart';

class CashFlowPage extends ConsumerStatefulWidget {
  const CashFlowPage({super.key});

  @override
  ConsumerState<CashFlowPage> createState() => _CashFlowPageState();
}

class _CashFlowPageState extends ConsumerState<CashFlowPage> {
  CashFlowPeriod _period = CashFlowPeriod.month;
  bool _hydratedFromUrl = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(
        recurringMaterialiseDueProvider(DateTime.now().toUtc()).future,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydratedFromUrl) return;
    _hydratedFromUrl = true;
    _period = _periodFromUri(
      GoRouter.of(context).routeInformationProvider.value.uri,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = context.formatters(ref);
    final request = CashFlowSummaryRequest(period: _period);
    final summaryAsync = ref.watch(cashFlowSummaryProvider(request));

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.cashFlowTitle),
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.event_repeat_outlined),
            onPress: () => context.push(kCashflowRecurringPath),
          ),
          FHeaderAction(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPress: () => context.push(kDividendCenterPath),
          ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: PageSkeletonShell<CashFlowSummary>(
          skeleton: const CashFlowSkeleton(),
          isLoading: summaryAsync.isLoading,
          child: summaryAsync.when(
            loading: () => const CashFlowSkeleton(),
            error: (error, _) => _LoadError(
              message: l10n.cashFlowLoadError('$error'),
              onRetry: () => ref.invalidate(cashFlowSummaryProvider(request)),
            ),
            data: (summary) => summary.buckets.isEmpty
                ? const _EmptyState()
                : _CashFlowContent(
                    period: _period,
                    summary: summary,
                    formatter: formatter,
                    now: ref.watch(cashFlowNowProvider),
                    onPeriodChanged: _changePeriod,
                  ),
          ),
        ),
      ),
    );
  }

  void _changePeriod(CashFlowPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    context.go('${AppRoutes.cashflow}?period=${period.name}');
  }
}

class _CashFlowContent extends StatelessWidget {
  const _CashFlowContent({
    required this.period,
    required this.summary,
    required this.formatter,
    required this.now,
    required this.onPeriodChanged,
  });

  final CashFlowPeriod period;
  final CashFlowSummary summary;
  final AppFormatters formatter;
  final DateTime now;
  final ValueChanged<CashFlowPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final keys = _visibleKeys(period, now.toUtc());
    final currentKey = keys.last;
    final model = _CashFlowViewModel.fromSummary(
      summary,
      visibleKeys: keys,
      currentKey: currentKey,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: AdaptiveContentFrame(
        maxWidth: AdaptiveMaxWidth.dashboard,
        padding: EdgeInsets.zero,
        layout: AdaptiveFrameLayout.twoColumn,
        columnBreakpoint: 1024,
        primaryFlex: 3,
        secondaryFlex: 2,
        sectionGap: AppSpacing.s16,
        columnGap: AppSpacing.s16,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PeriodSelector(period: period, onChanged: onPeriodChanged),
            const SizedBox(height: AppSpacing.s16),
            _KpiGrid(model: model, formatter: formatter),
          ],
        ),
        primary: _ChartsPanel(model: model, formatter: formatter),
        secondary: _CategoryPanel(model: model, formatter: formatter),
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.period, required this.onChanged});

  final CashFlowPeriod period;
  final ValueChanged<CashFlowPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        for (final candidate in CashFlowPeriod.values)
          _PeriodChip(
            label: _periodLabel(l10n, candidate),
            selected: candidate == period,
            onTap: () => onChanged(candidate),
          ),
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.muted,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: context.theme.typography.sm.copyWith(
            color: selected ? colors.primaryForeground : colors.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.model, required this.formatter});

  final _CashFlowViewModel model;
  final AppFormatters formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    final tiles = <Widget>[
      _KpiTile(
        label: l10n.cashFlowKpiInflow,
        money: model.currentInflow,
        formatter: formatter,
        tint: semantic.success,
      ),
      _KpiTile(
        label: l10n.cashFlowKpiOutflow,
        money: model.currentOutflow,
        formatter: formatter,
        tint: semantic.danger,
      ),
      _KpiTile(
        label: l10n.cashFlowKpiNet,
        money: model.currentNet,
        formatter: formatter,
        tint: model.currentNet.baseAmount < Decimal.zero
            ? semantic.danger
            : semantic.success,
        signed: true,
      ),
    ];
    // Intrinsic-height tiles instead of a fixed-aspect GridView: never
    // overflows under large text-scale or intermediate widths.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i != 0) const SizedBox(width: AppSpacing.s12),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i != 0) const SizedBox(height: AppSpacing.s12),
              tiles[i],
            ],
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.money,
    required this.formatter,
    required this.tint,
    this.signed = false,
  });

  final String label;
  final _MoneyBreakdown money;
  final AppFormatters formatter;
  final Color tint;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          _DualMoneyText(
            money: money,
            formatter: formatter,
            signed: signed,
            style: TypographyTokens.numericTitle.copyWith(
              color: tint,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartsPanel extends StatelessWidget {
  const _ChartsPanel({required this.model, required this.formatter});

  final _CashFlowViewModel model;
  final AppFormatters formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    final locale = Localizations.localeOf(context).toString();
    final axis = ValueAxis.currency(
      currencyCode: model.baseCurrency,
      showGrid: true,
      locale: locale,
    );
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cashFlowIncomeExpenseTitle,
            style: context.theme.typography.md.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          NwBarChart(
            series: [
              CategorySeries(
                name: l10n.cashFlowKpiInflow,
                data: model.periods
                    .map(
                      (period) => CategoryDatum(
                        label: period.label,
                        value: period.inflow.toDouble(),
                        colorOverride: semantic.success,
                      ),
                    )
                    .toList(),
              ),
              CategorySeries(
                name: l10n.cashFlowKpiOutflow,
                data: model.periods
                    .map(
                      (period) => CategoryDatum(
                        label: period.label,
                        value: period.outflow.toDouble(),
                        colorOverride: semantic.danger,
                      ),
                    )
                    .toList(),
              ),
            ],
            yAxis: axis,
            aspectRatio: 16 / 7,
            barWidth: 10,
            semanticLabel: l10n.cashFlowIncomeExpenseTitle,
          ),
          const SizedBox(height: AppSpacing.s20),
          Text(
            l10n.cashFlowNetTrendTitle,
            style: context.theme.typography.md.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          SizedBox(
            height: 220,
            child: NwLineChart(
              series: [
                ChartSeries(
                  name: l10n.cashFlowKpiNet,
                  points: model.periods
                      .map(
                        (period) => ChartPoint(
                          x: period.date.millisecondsSinceEpoch.toDouble(),
                          y: period.net.toDouble(),
                        ),
                      )
                      .toList(),
                  colorOverride: context.theme.colors.primary,
                ),
              ],
              xAxis: TimeAxis(locale: locale, showGrid: false),
              yAxis: axis,
              interpolation: ChartInterpolation.linear,
              semanticLabel: l10n.cashFlowNetTrendTitle,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({required this.model, required this.formatter});

  final _CashFlowViewModel model;
  final AppFormatters formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slices = model.categories
        .map(
          (category) => Slice(
            label: _kindLabel(l10n, category.kind),
            value: category.amount.toDouble(),
          ),
        )
        .toList();
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cashFlowCategoryTitle,
            style: context.theme.typography.md.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          NwPieChart(
            slices: slices,
            aspectRatio: 4 / 3,
            semanticLabel: l10n.cashFlowCategoryTitle,
          ),
          const SizedBox(height: AppSpacing.s12),
          for (final category in model.categories)
            _CategoryRow(
              category: category,
              formatter: formatter,
              total: model.categoryTotal,
            ),
          if (model.categories.any((c) => c.kind == CashFlowKind.dividend))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s12),
              child: FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.push(kDividendCenterPath),
                prefix: const Icon(Icons.account_balance_wallet_outlined),
                child: Text(l10n.cashFlowViewDividendCenter),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.formatter,
    required this.total,
  });

  final _CategoryTotal category;
  final AppFormatters formatter;
  final Decimal total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final percent = total == Decimal.zero
        ? 0
        : (category.amount / total).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _kindLabel(l10n, category.kind),
              style: context.theme.typography.sm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatter.percent(percent, decimalDigits: 0),
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Flexible(
            child: Text(
              formatter.currency(category.amount, code: category.currency),
              style: TypographyTokens.numericBody.copyWith(
                color: context.theme.colors.foreground,
              ),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DualMoneyText extends StatefulWidget {
  const _DualMoneyText({
    required this.money,
    required this.formatter,
    required this.style,
    this.signed = false,
  });

  final _MoneyBreakdown money;
  final AppFormatters formatter;
  final TextStyle style;
  final bool signed;

  @override
  State<_DualMoneyText> createState() => _DualMoneyTextState();
}

class _DualMoneyTextState extends State<_DualMoneyText> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final text = _showOriginal
        ? widget.money.formatOriginal(widget.formatter, signed: widget.signed)
        : widget.money.formatBase(widget.formatter, signed: widget.signed);
    return GestureDetector(
      onLongPressStart: (_) => setState(() => _showOriginal = true),
      onLongPressEnd: (_) => setState(() => _showOriginal = false),
      onLongPressCancel: () => setState(() => _showOriginal = false),
      child: Text(
        text,
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: context.theme.colors.destructive,
            size: 32,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: onRetry,
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 56,
              color: context.theme.colors.primary,
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.cashFlowEmptyTitle,
              style: context.theme.typography.lg,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.cashFlowEmptyBody,
              style: context.theme.typography.sm.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CashFlowViewModel {
  const _CashFlowViewModel({
    required this.baseCurrency,
    required this.periods,
    required this.currentInflow,
    required this.currentOutflow,
    required this.currentNet,
    required this.categories,
    required this.categoryTotal,
  });

  final String baseCurrency;
  final List<_PeriodTotal> periods;
  final _MoneyBreakdown currentInflow;
  final _MoneyBreakdown currentOutflow;
  final _MoneyBreakdown currentNet;
  final List<_CategoryTotal> categories;
  final Decimal categoryTotal;

  factory _CashFlowViewModel.fromSummary(
    CashFlowSummary summary, {
    required List<String> visibleKeys,
    required String currentKey,
  }) {
    final byPeriod = {
      for (final key in visibleKeys)
        key: _PeriodAcc(
          key: key,
          label: _shortPeriodLabel(key, summary.period),
          date: _periodDate(key, summary.period),
        ),
    };
    final current = _CurrentAcc(summary.baseCurrency);
    final categoryAcc = <CashFlowKind, Decimal>{};

    for (final bucket in summary.buckets) {
      final amount = bucket.totalInBase.amount;
      final periodAcc = byPeriod[bucket.key];
      if (periodAcc != null) {
        if (_isIncomeKind(bucket.kind) && amount > Decimal.zero) {
          periodAcc.inflow += amount;
        } else if (bucket.kind == CashFlowKind.expense) {
          periodAcc.outflow += amount.abs();
        }
      }
      if (bucket.key == currentKey) {
        current.add(bucket);
        final magnitude = amount.abs();
        if (magnitude > Decimal.zero) {
          categoryAcc.update(
            bucket.kind,
            (value) => value + magnitude,
            ifAbsent: () => magnitude,
          );
        }
      }
    }

    final categories =
        categoryAcc.entries
            .map(
              (entry) => _CategoryTotal(
                kind: entry.key,
                amount: entry.value,
                currency: summary.baseCurrency,
              ),
            )
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));
    final categoryTotal = categories.fold<Decimal>(
      Decimal.zero,
      (sum, category) => sum + category.amount,
    );

    return _CashFlowViewModel(
      baseCurrency: summary.baseCurrency,
      periods: List.unmodifiable(byPeriod.values),
      currentInflow: current.inflow,
      currentOutflow: current.outflow,
      currentNet: current.net,
      categories: List.unmodifiable(categories),
      categoryTotal: categoryTotal,
    );
  }
}

class _PeriodAcc {
  _PeriodAcc({required this.key, required this.label, required this.date});

  final String key;
  final String label;
  final DateTime date;
  Decimal inflow = Decimal.zero;
  Decimal outflow = Decimal.zero;

  Decimal get net => inflow - outflow;
}

typedef _PeriodTotal = _PeriodAcc;

class _CurrentAcc {
  _CurrentAcc(this.baseCurrency);

  final String baseCurrency;
  Decimal inflowBase = Decimal.zero;
  Decimal outflowBase = Decimal.zero;
  Decimal netBase = Decimal.zero;
  final inflowOriginals = <String, Decimal>{};
  final outflowOriginals = <String, Decimal>{};
  final netOriginals = <String, Decimal>{};

  void add(CashFlowBucket bucket) {
    final amount = bucket.totalInBase.amount;
    final original = bucket.originalTotal.amount;
    netBase += amount;
    _add(netOriginals, bucket.currency, original);
    if (amount > Decimal.zero) {
      inflowBase += amount;
      _add(inflowOriginals, bucket.currency, original.abs());
    } else if (amount < Decimal.zero) {
      outflowBase += amount.abs();
      _add(outflowOriginals, bucket.currency, original.abs());
    }
  }

  _MoneyBreakdown get inflow => _MoneyBreakdown(
    baseAmount: inflowBase,
    baseCurrency: baseCurrency,
    originals: Map.unmodifiable(inflowOriginals),
  );

  _MoneyBreakdown get outflow => _MoneyBreakdown(
    baseAmount: outflowBase,
    baseCurrency: baseCurrency,
    originals: Map.unmodifiable(outflowOriginals),
  );

  _MoneyBreakdown get net => _MoneyBreakdown(
    baseAmount: netBase,
    baseCurrency: baseCurrency,
    originals: Map.unmodifiable(netOriginals),
  );
}

class _MoneyBreakdown {
  const _MoneyBreakdown({
    required this.baseAmount,
    required this.baseCurrency,
    required this.originals,
  });

  final Decimal baseAmount;
  final String baseCurrency;
  final Map<String, Decimal> originals;

  String formatBase(AppFormatters formatter, {required bool signed}) {
    if (signed) {
      return formatter.signedMoney(baseAmount, unit: baseCurrency);
    }
    return formatter.currency(baseAmount.abs(), code: baseCurrency);
  }

  String formatOriginal(AppFormatters formatter, {required bool signed}) {
    if (originals.isEmpty) return formatBase(formatter, signed: signed);
    final entries = originals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map(
          (entry) => signed
              ? formatter.signedMoney(entry.value, unit: entry.key)
              : formatter.currency(entry.value.abs(), code: entry.key),
        )
        .join(' / ');
  }
}

class _CategoryTotal {
  const _CategoryTotal({
    required this.kind,
    required this.amount,
    required this.currency,
  });

  final CashFlowKind kind;
  final Decimal amount;
  final String currency;
}

void _add(Map<String, Decimal> map, String currency, Decimal amount) {
  map.update(currency, (value) => value + amount, ifAbsent: () => amount);
}

bool _isIncomeKind(CashFlowKind kind) {
  return switch (kind) {
    CashFlowKind.salary ||
    CashFlowKind.dividend ||
    CashFlowKind.interest ||
    CashFlowKind.capitalGains ||
    CashFlowKind.otherIncome => true,
    CashFlowKind.expense ||
    CashFlowKind.transfer ||
    CashFlowKind.opening ||
    CashFlowKind.other => false,
  };
}

CashFlowPeriod _periodFromUri(Uri uri) {
  final value = uri.queryParameters['period'];
  return switch (value) {
    'quarter' => CashFlowPeriod.quarter,
    'year' => CashFlowPeriod.year,
    _ => CashFlowPeriod.month,
  };
}

String _periodLabel(AppLocalizations l10n, CashFlowPeriod period) {
  return switch (period) {
    CashFlowPeriod.month => l10n.cashFlowPeriodMonth,
    CashFlowPeriod.quarter => l10n.cashFlowPeriodQuarter,
    CashFlowPeriod.year => l10n.cashFlowPeriodYear,
  };
}

String _kindLabel(AppLocalizations l10n, CashFlowKind kind) {
  return switch (kind) {
    CashFlowKind.salary => l10n.cashFlowKindSalary,
    CashFlowKind.dividend => l10n.cashFlowKindDividend,
    CashFlowKind.interest => l10n.cashFlowKindInterest,
    CashFlowKind.capitalGains => l10n.cashFlowKindCapitalGains,
    CashFlowKind.otherIncome => l10n.cashFlowKindOtherIncome,
    CashFlowKind.expense => l10n.cashFlowKindExpense,
    CashFlowKind.transfer => l10n.cashFlowKindTransfer,
    CashFlowKind.opening => l10n.cashFlowKindOpening,
    CashFlowKind.other => l10n.cashFlowKindOther,
  };
}

List<String> _visibleKeys(CashFlowPeriod period, DateTime now) {
  final count = switch (period) {
    CashFlowPeriod.month => 12,
    CashFlowPeriod.quarter => 8,
    CashFlowPeriod.year => 5,
  };
  return [
    for (var i = count - 1; i >= 0; i--)
      _periodKey(_minusPeriods(now, period, i), period),
  ];
}

DateTime _minusPeriods(DateTime date, CashFlowPeriod period, int count) {
  return switch (period) {
    CashFlowPeriod.month => DateTime.utc(date.year, date.month - count, 1),
    CashFlowPeriod.quarter => DateTime.utc(
      date.year,
      date.month - count * 3,
      1,
    ),
    CashFlowPeriod.year => DateTime.utc(date.year - count, 1, 1),
  };
}

String _periodKey(DateTime date, CashFlowPeriod period) {
  return switch (period) {
    CashFlowPeriod.month =>
      '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}',
    CashFlowPeriod.quarter =>
      '${date.year.toString().padLeft(4, '0')}-Q'
          '${((date.month - 1) ~/ 3) + 1}',
    CashFlowPeriod.year => date.year.toString().padLeft(4, '0'),
  };
}

DateTime _periodDate(String key, CashFlowPeriod period) {
  return switch (period) {
    CashFlowPeriod.month => DateTime.utc(
      int.parse(key.substring(0, 4)),
      int.parse(key.substring(5, 7)),
      1,
    ),
    CashFlowPeriod.quarter => DateTime.utc(
      int.parse(key.substring(0, 4)),
      (int.parse(key.substring(6, 7)) - 1) * 3 + 1,
      1,
    ),
    CashFlowPeriod.year => DateTime.utc(int.parse(key), 1, 1),
  };
}

String _shortPeriodLabel(String key, CashFlowPeriod period) {
  return switch (period) {
    CashFlowPeriod.month => key.substring(5, 7),
    CashFlowPeriod.quarter => key.substring(5),
    CashFlowPeriod.year => key,
  };
}
