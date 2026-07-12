part of '../cashflow_page.dart';

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
    void openActivity(ActivityKind? kind) {
      context.go(cashFlowActivityRoute(period: period, now: now, kind: kind));
    }

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
            _KpiGrid(
              model: model,
              formatter: formatter,
              onOpenIncome: () => openActivity(ActivityKind.income),
              onOpenExpenses: () => openActivity(ActivityKind.expense),
              onOpenNet: () => openActivity(null),
            ),
          ],
        ),
        primary: _ChartsPanel(model: model, formatter: formatter),
        secondary: _CategoryPanel(
          model: model,
          formatter: formatter,
          onOpenIncome: () => openActivity(ActivityKind.income),
          onOpenExpenses: () => openActivity(ActivityKind.expense),
        ),
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
    return SegmentedRow<CashFlowPeriod>(
      options: CashFlowPeriod.values,
      value: period,
      labelOf: (candidate) => _periodLabel(l10n, candidate),
      onChanged: onChanged,
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.model,
    required this.formatter,
    required this.onOpenIncome,
    required this.onOpenExpenses,
    required this.onOpenNet,
  });

  final _CashFlowViewModel model;
  final AppFormatters formatter;
  final VoidCallback onOpenIncome;
  final VoidCallback onOpenExpenses;
  final VoidCallback onOpenNet;

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
        onPress: onOpenIncome,
      ),
      _KpiTile(
        label: l10n.cashFlowKpiOutflow,
        money: model.currentOutflow,
        formatter: formatter,
        tint: semantic.danger,
        onPress: onOpenExpenses,
      ),
      _KpiTile(
        label: l10n.cashFlowKpiNet,
        money: model.currentNet,
        formatter: formatter,
        tint: model.currentNet.baseAmount < Decimal.zero
            ? semantic.danger
            : semantic.success,
        signed: true,
        onPress: onOpenNet,
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
    required this.onPress,
    this.signed = false,
  });

  final String label;
  final _MoneyBreakdown money;
  final AppFormatters formatter;
  final Color tint;
  final bool signed;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onPress: onPress,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s8),
          _DualMoneyText(
            money: money,
            formatter: formatter,
            signed: signed,
            style: TypographyTokens.numericTitleStrong.copyWith(color: tint),
          ),
          const SizedBox(height: AppSpacing.s8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.sm,
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
