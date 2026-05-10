import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/fire_projection.dart';
import 'fire_goal_form.dart';
import 'fire_progress_gauge.dart';
import 'fire_scenarios_chart.dart';

class FireUnconfiguredBody extends StatelessWidget {
  const FireUnconfiguredBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: Spacing.pageMobile,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.flag_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: Spacing.s16),
            Text(
              l10n.fireEmptyTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.s8),
            Text(
              l10n.fireEmptyHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.s24),
            FButton(
              variant: FButtonVariant.primary,
              onPress: () => showFireGoalSheet(context),
              prefix: const Icon(Icons.add, size: 16),
              child: Text(l10n.fireEmptySetGoalCta),
            ),
          ],
        ),
      ),
    );
  }
}

class FireConfiguredBody extends ConsumerWidget {
  const FireConfiguredBody({super.key, required this.view});

  final FireDashboardView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProgressHeaderCard(view: view, formatters: formatters),
        const SizedBox(height: Spacing.s12),
        _CountdownCard(view: view, formatters: formatters),
      ],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectionCard(view: view),
        const SizedBox(height: Spacing.s12),
        _ScenariosTable(view: view),
        const SizedBox(height: Spacing.s12),
        _SafeWithdrawalCard(view: view, formatters: formatters),
        const SizedBox(height: Spacing.s12),
        _SensitivityCard(view: view),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        return ListView(
          padding: isWide ? Spacing.pageWide : Spacing.pageMobile,
          children: [
            ResponsiveTwoColumn(left: left, right: right),
            const SizedBox(height: Spacing.s16),
            FButton(
              variant: FButtonVariant.outline,
              onPress: () => showFireGoalSheet(context),
              prefix: const Icon(Icons.edit_outlined, size: 16),
              child: Text(l10n.fireEditGoal),
            ),
          ],
        );
      },
    );
  }
}

class _ProgressHeaderCard extends StatelessWidget {
  const _ProgressHeaderCard({required this.view, required this.formatters});

  final FireDashboardView view;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final ratio = view.progressRatio ?? 0;
    final percentLabel = formatters.percent(
      ratio,
      decimalDigits: ratio >= 0.1 ? 0 : 1,
    );
    final current = view.currentNetWorth.toDouble();
    final target = view.goal.targetAmount.toDouble();
    final gap = target - current;

    return FCard.raw(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.fireProgressTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.s12),
            Center(
              child: FireProgressGauge(
                progress: ratio,
                centerLabel: percentLabel,
                caption: l10n.fireProgressGaugeCaption,
              ),
            ),
            const SizedBox(height: Spacing.s16),
            _LabelValueRow(
              label: l10n.fireProgressCurrent,
              child: AnimatedMoneyText(
                amount: current,
                currencyCode: view.baseCurrency,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: Spacing.s4),
            _LabelValueRow(
              label: l10n.fireProgressTarget,
              child: AnimatedMoneyText(
                amount: target,
                currencyCode: view.baseCurrency,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: Spacing.s4),
            _LabelValueRow(
              label: l10n.fireProgressGap,
              child: AnimatedMoneyText(
                amount: gap > 0 ? gap : 0,
                currencyCode: view.baseCurrency,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.view, required this.formatters});

  final FireDashboardView view;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final months = view.sensitivity.baselineMonths;
    final referenceLabel = _baselineTier(view) == FireScenarioTier.live
        ? l10n.fireScenarioLive
        : l10n.fireScenarioNeutral;

    final body = months == null
        ? Text(l10n.fireCountdownUnreachable, style: theme.textTheme.bodyMedium)
        : months == 0
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.fireCountdownReachedTitle,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: Spacing.s4),
              Text(
                l10n.fireCountdownReachedSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatYearsMonths(l10n, months),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: Spacing.s4),
              Text(
                l10n.fireCountdownDaysAprox(_approxDays(months)),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );

    return FCard.raw(
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.fireCountdownTitle(referenceLabel),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.s8),
            body,
          ],
        ),
      ),
    );
  }

  static FireScenarioTier _baselineTier(FireDashboardView view) {
    return view.scenarios.any((s) => s.tier == FireScenarioTier.live)
        ? FireScenarioTier.live
        : FireScenarioTier.neutral;
  }

  static int _approxDays(int months) => (months * 30.44).round();
}

class _ProjectionCard extends StatelessWidget {
  const _ProjectionCard({required this.view});

  final FireDashboardView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return FCard.raw(
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.fireProjectionTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.s4),
            Text(
              l10n.fireProjectionSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.s12),
            LayoutBuilder(
              builder: (context, c) => FireScenariosChart(
                scenarios: view.scenarios,
                baseCurrency: view.baseCurrency,
                locale: Localizations.localeOf(context).toString(),
                scenarioLabel: (tier) => _scenarioLabel(l10n, tier),
                aspectRatio: chartAspectFor(c.maxWidth),
              ),
            ),
            const SizedBox(height: Spacing.s8),
            _ScenarioLegend(view: view),
          ],
        ),
      ),
    );
  }
}

class _ScenarioLegend extends StatelessWidget {
  const _ScenarioLegend({required this.view});

  final FireDashboardView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final palette = ChartPalette.of(context);
    return Wrap(
      spacing: Spacing.s12,
      runSpacing: Spacing.s8,
      children: [
        for (final s in view.scenarios)
          _LegendDot(
            color: _colorForTier(context, palette, s.tier),
            label:
                '${_scenarioLabel(l10n, s.tier)} '
                '(${(s.annualReturn * 100).toStringAsFixed(1)}%)',
          ),
        _LegendDot(
          color: theme.colorScheme.onSurfaceVariant,
          label: l10n.fireProjectionTargetLineLegend,
          dashed: true,
        ),
      ],
    );
  }
}

class _ScenariosTable extends StatelessWidget {
  const _ScenariosTable({required this.view});

  final FireDashboardView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return FCard.raw(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.s16,
              Spacing.s16,
              Spacing.s16,
              Spacing.s8,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.fireScenariosTableTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          for (final scenario in view.scenarios)
            FTile(
              title: Text(_scenarioLabel(l10n, scenario.tier)),
              subtitle: Text(
                l10n.fireScenarioRateLabel(
                  (scenario.annualReturn * 100).toStringAsFixed(1),
                ),
              ),
              suffix: SizedBox(
                width: 110,
                child: Text(
                  scenario.monthsToTarget == null
                      ? l10n.fireCountdownUnreachableShort
                      : _formatYearsMonths(l10n, scenario.monthsToTarget!),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SafeWithdrawalCard extends StatelessWidget {
  const _SafeWithdrawalCard({required this.view, required this.formatters});

  final FireDashboardView view;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final monthly = view.safeMonthlyWithdrawalAmount;
    final surplus = view.safeWithdrawalSurplus;
    final monthlyExpenses = view.goal.monthlyExpenses.toDouble();

    final coverageHint = monthlyExpenses == 0
        ? l10n.fireSafeWithdrawalNoExpenses
        : surplus >= 0
        ? l10n.fireSafeWithdrawalCovers(
            formatters.currency(
              _toFixedDecimal(surplus.abs()),
              code: view.baseCurrency,
            ),
          )
        : l10n.fireSafeWithdrawalShortfall(
            formatters.currency(
              _toFixedDecimal(surplus.abs()),
              code: view.baseCurrency,
            ),
          );

    return FCard.raw(
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.fireSafeWithdrawalTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              l10n.fireSafeWithdrawalSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.s12),
            _LabelValueRow(
              label: l10n.fireSafeWithdrawalMonthly,
              value: formatters.currency(
                _toFixedDecimal(monthly),
                code: view.baseCurrency,
              ),
            ),
            const SizedBox(height: Spacing.s4),
            _LabelValueRow(
              label: l10n.fireSafeWithdrawalAnnual,
              value: formatters.currency(
                _toFixedDecimal(monthly * 12),
                code: view.baseCurrency,
              ),
            ),
            const SizedBox(height: Spacing.s8),
            Text(
              coverageHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: surplus >= 0 || monthlyExpenses == 0
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensitivityCard extends StatelessWidget {
  const _SensitivityCard({required this.view});

  final FireDashboardView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final s = view.sensitivity;

    return FCard.raw(
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.fireSensitivityTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.s4),
            Text(
              l10n.fireSensitivitySubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.s12),
            _LabelValueRow(
              label: l10n.fireSensitivityHigherSurplus,
              value: _formatOptionalMonths(l10n, s.highSurplusMonths),
            ),
            const SizedBox(height: Spacing.s4),
            _LabelValueRow(
              label: l10n.fireSensitivityBaseline,
              value: _formatOptionalMonths(l10n, s.baselineMonths),
            ),
            const SizedBox(height: Spacing.s4),
            _LabelValueRow(
              label: l10n.fireSensitivityLowerSurplus,
              value: _formatOptionalMonths(l10n, s.lowSurplusMonths),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({required this.label, this.value, this.child})
    : assert(
        value != null || child != null,
        'either value or child must be provided',
      );

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: Spacing.s8),
        child ?? Text(value!, style: theme.textTheme.titleSmall),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: dashed ? null : color,
            border: dashed ? Border.all(color: color, width: 1.5) : null,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: Spacing.s4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

String _formatOptionalMonths(AppLocalizations l10n, int? months) {
  if (months == null) return l10n.fireCountdownUnreachableShort;
  if (months == 0) return l10n.fireScenarioReachedNow;
  return _formatYearsMonths(l10n, months);
}

String _formatYearsMonths(AppLocalizations l10n, int totalMonths) {
  final years = totalMonths ~/ 12;
  final months = totalMonths % 12;
  if (years == 0) return l10n.fireCountdownMonthsOnly(months);
  if (months == 0) return l10n.fireCountdownYearsOnly(years);
  return l10n.fireCountdownYearsMonths(years, months);
}

String _scenarioLabel(AppLocalizations l10n, FireScenarioTier tier) {
  switch (tier) {
    case FireScenarioTier.conservative:
      return l10n.fireScenarioConservative;
    case FireScenarioTier.neutral:
      return l10n.fireScenarioNeutral;
    case FireScenarioTier.aggressive:
      return l10n.fireScenarioAggressive;
    case FireScenarioTier.live:
      return l10n.fireScenarioLive;
  }
}

Color _colorForTier(
  BuildContext context,
  ChartPalette palette,
  FireScenarioTier tier,
) {
  switch (tier) {
    case FireScenarioTier.conservative:
      return palette.accentAt(3);
    case FireScenarioTier.neutral:
      return palette.accentAt(6);
    case FireScenarioTier.aggressive:
      return palette.accentAt(2);
    case FireScenarioTier.live:
      return Theme.of(context).colorScheme.primary;
  }
}

Decimal _toFixedDecimal(double value) {
  return Decimal.parse(value.toStringAsFixed(2));
}
