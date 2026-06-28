import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/fire_projection.dart';
import 'fire_buckets_card.dart';
import 'fire_goal_form.dart';
import 'fire_progress_gauge.dart';
import 'fire_review_card.dart';
import 'fire_scenarios_chart.dart';
import 'fire_simulations_card.dart';
import 'fire_state_hero_card.dart';
import 'fire_stress_tests_card.dart';

class FireUnconfiguredBody extends StatelessWidget {
  const FireUnconfiguredBody({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.flag,
      iconSize: 64,
      title: l10n.fireEmptyTitle,
      message: l10n.fireEmptyHint,
      action: FButton(
        variant: FButtonVariant.primary,
        onPress: () => showFireGoalSheet(context),
        prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
        child: Text(l10n.fireEmptySetGoalCta),
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
        const FireStateHeroCard(),
        const SizedBox(height: AppSpacing.s12),
        const FireBucketsCard(),
        const SizedBox(height: AppSpacing.s12),
        _ProgressHeaderCard(view: view, formatters: formatters),
        const SizedBox(height: AppSpacing.s12),
        _CountdownCard(view: view, formatters: formatters),
      ],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FireStressTestsCard(),
        const SizedBox(height: AppSpacing.s12),
        const FireSimulationsCard(),
        const SizedBox(height: AppSpacing.s12),
        _ProjectionCard(view: view),
        const SizedBox(height: AppSpacing.s12),
        _ScenariosTable(view: view),
        const SizedBox(height: AppSpacing.s12),
        _SafeWithdrawalCard(view: view, formatters: formatters),
        const SizedBox(height: AppSpacing.s12),
        _SensitivityCard(view: view),
        const SizedBox(height: AppSpacing.s12),
        const FireReviewCard(),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        return ListView(
          padding: isWide
              ? const EdgeInsets.all(AppSpacing.s24)
              : const EdgeInsets.all(AppSpacing.s16),
          children: [
            ResponsiveTwoColumn(left: left, right: right),
            const SizedBox(height: AppSpacing.s16),
            FButton(
              variant: FButtonVariant.outline,
              onPress: () => showFireGoalSheet(context),
              prefix: const Icon(FLucideIcons.pencil, size: AppIconSizes.sm),
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
    final l10n = AppLocalizations.of(context);
    final ratio = view.progressRatio ?? 0;
    final percentLabel = formatters.percent(
      ratio,
      decimalDigits: ratio >= 0.1 ? 0 : 1,
    );
    final current = view.currentNetWorth.toDouble();
    final target = view.goal.targetAmount.toDouble();
    final gap = target - current;

    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.fireProgressTitle, style: context.theme.typography.body.md),
          const SizedBox(height: AppSpacing.s12),
          Center(
            child: FireProgressGauge(
              progress: ratio,
              centerLabel: percentLabel,
              caption: l10n.fireProgressGaugeCaption,
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          _LabelValueRow(
            label: l10n.fireProgressCurrent,
            child: AnimatedMoneyText(
              amount: current,
              currencyCode: view.baseCurrency,
              style: context.theme.typography.body.sm,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          _LabelValueRow(
            label: l10n.fireProgressTarget,
            child: AnimatedMoneyText(
              amount: target,
              currencyCode: view.baseCurrency,
              style: context.theme.typography.body.sm,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          _LabelValueRow(
            label: l10n.fireProgressGap,
            child: AnimatedMoneyText(
              amount: gap > 0 ? gap : 0,
              currencyCode: view.baseCurrency,
              style: context.theme.typography.body.sm,
            ),
          ),
        ],
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
    final l10n = AppLocalizations.of(context);
    final months = view.sensitivity.baselineMonths;
    final referenceLabel = _baselineTier(view) == FireScenarioTier.live
        ? l10n.fireScenarioLive
        : l10n.fireScenarioNeutral;

    final body = months == null
        ? Text(
            l10n.fireCountdownUnreachable,
            style: context.theme.typography.body.sm,
          )
        : months == 0
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.fireCountdownReachedTitle,
                style: context.theme.typography.body.xl,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                l10n.fireCountdownReachedSubtitle,
                style: context.bodyCaptionStyle,
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatYearsMonths(l10n, months),
                style: context.theme.typography.body.xl,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                l10n.fireCountdownDaysAprox(_approxDays(months)),
                style: context.bodyCaptionStyle,
              ),
            ],
          );

    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.fireCountdownTitle(referenceLabel),
            style: context.theme.typography.body.md,
          ),
          const SizedBox(height: AppSpacing.s8),
          body,
        ],
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
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.fireProjectionTitle,
            style: context.theme.typography.body.md,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(l10n.fireProjectionSubtitle, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s12),
          LayoutBuilder(
            builder: (context, c) => FireScenariosChart(
              scenarios: view.scenarios,
              baseCurrency: view.baseCurrency,
              locale: Localizations.localeOf(context).toString(),
              scenarioLabel: (tier) => _scenarioLabel(l10n, tier),
              aspectRatio: chartAspectFor(c.maxWidth),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          _ScenarioLegend(view: view),
        ],
      ),
    );
  }
}

class _ScenarioLegend extends StatelessWidget {
  const _ScenarioLegend({required this.view});

  final FireDashboardView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ChartPalette.of(context);
    return Wrap(
      spacing: AppSpacing.s12,
      runSpacing: AppSpacing.s8,
      children: [
        for (final s in view.scenarios)
          _LegendDot(
            color: _colorForTier(context, palette, s.tier),
            label:
                '${_scenarioLabel(l10n, s.tier)} '
                '(${(s.annualReturn * 100).toStringAsFixed(1)}%)',
          ),
        _LegendDot(
          color: context.theme.colors.mutedForeground,
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
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s16,
              AppSpacing.s16,
              AppSpacing.s8,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.fireScenariosTableTitle,
                style: context.theme.typography.body.md,
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
                width: AppControlWidths.scenarioSuffix,
                child: Text(
                  scenario.monthsToTarget == null
                      ? l10n.fireCountdownUnreachableShort
                      : _formatYearsMonths(l10n, scenario.monthsToTarget!),
                  textAlign: TextAlign.end,
                  style: context.theme.typography.body.sm,
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

    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.fireSafeWithdrawalTitle,
            style: context.theme.typography.body.md,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(l10n.fireSafeWithdrawalSubtitle, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s12),
          _LabelValueRow(
            label: l10n.fireSafeWithdrawalMonthly,
            value: formatters.currency(
              _toFixedDecimal(monthly),
              code: view.baseCurrency,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          _LabelValueRow(
            label: l10n.fireSafeWithdrawalAnnual,
            value: formatters.currency(
              _toFixedDecimal(monthly * 12),
              code: view.baseCurrency,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            coverageHint,
            style: context.captionStyle.copyWith(
              color: surplus >= 0 || monthlyExpenses == 0
                  ? context.theme.colors.mutedForeground
                  : context.theme.colors.destructive,
            ),
          ),
        ],
      ),
    );
  }
}

class _SensitivityCard extends StatelessWidget {
  const _SensitivityCard({required this.view});

  final FireDashboardView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = view.sensitivity;

    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.fireSensitivityTitle,
            style: context.theme.typography.body.md,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(l10n.fireSensitivitySubtitle, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s12),
          _LabelValueRow(
            label: l10n.fireSensitivityHigherSurplus,
            value: _formatOptionalMonths(l10n, s.highSurplusMonths),
          ),
          const SizedBox(height: AppSpacing.s4),
          _LabelValueRow(
            label: l10n.fireSensitivityBaseline,
            value: _formatOptionalMonths(l10n, s.baselineMonths),
          ),
          const SizedBox(height: AppSpacing.s4),
          _LabelValueRow(
            label: l10n.fireSensitivityLowerSurplus,
            value: _formatOptionalMonths(l10n, s.lowSurplusMonths),
          ),
        ],
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: context.bodyCaptionStyle)),
        const SizedBox(width: AppSpacing.s8),
        child ?? Text(value!, style: context.theme.typography.body.sm),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: dashed ? null : color,
            border: dashed
                ? Border.all(color: color, width: AppStroke.medium)
                : null,
            borderRadius: BorderRadius.circular(AppRadius.xxs),
          ),
        ),
        const SizedBox(width: AppSpacing.s4),
        Text(label, style: context.theme.typography.body.xs),
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
      return context.theme.colors.primary;
  }
}

Decimal _toFixedDecimal(double value) => DecimalX.fromDouble(value);
