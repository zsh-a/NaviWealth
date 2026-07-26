import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../../../../core/format/formatters.dart';
import '../data/fire_providers.dart';
import '../domain/fire_projection.dart';
import 'fire_goal_form.dart';
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
      action: AppActionButton(
        mainAxisSize: MainAxisSize.min,
        onPress: () => showFireGoalSheet(context),
        prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
        child: Text(l10n.fireEmptySetGoalCta),
      ),
    );
  }
}

/// Slim FIRE workspace: hero story, projection, collapsible resilience.
class FireConfiguredBody extends ConsumerWidget {
  const FireConfiguredBody({super.key, required this.view});

  final FireDashboardView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FireStateHeroCard(view: view),
        const SizedBox(height: AppPageRhythm.module),
        const _FireBudgetPosture(),
        const SizedBox(height: AppPageRhythm.section),
        _ProjectionCard(view: view),
      ],
    );

    const depth = _FireDepthSection();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        return ListView(
          padding: EdgeInsets.all(isWide ? AppSpacing.s24 : AppSpacing.s16),
          children: [
            if (isWide)
              ResponsiveTwoColumn(left: primary, right: depth)
            else ...[
              primary,
              const SizedBox(height: AppPageRhythm.section),
              depth,
            ],
          ],
        );
      },
    );
  }
}

class _FireBudgetPosture extends ConsumerWidget {
  const _FireBudgetPosture();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signalAsync = ref.watch(fireBudgetSignalProvider);
    return signalAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (signal) {
        final l10n = AppLocalizations.of(context);
        final semantic = SemanticColors.of(context);
        final (icon, color, title, detail) = switch (signal) {
          BudgetSignal.noData => (
            FLucideIcons.walletCards,
            context.theme.colors.mutedForeground,
            l10n.fireBudgetNoDataTitle,
            l10n.fireBudgetNoDataDetail,
          ),
          BudgetSignal.comfortable => (
            FLucideIcons.circleCheck,
            semantic.success,
            l10n.fireBudgetComfortableTitle,
            l10n.fireBudgetComfortableDetail,
          ),
          BudgetSignal.strained => (
            FLucideIcons.gauge,
            semantic.warning,
            l10n.fireBudgetStrainedTitle,
            l10n.fireBudgetStrainedDetail,
          ),
          BudgetSignal.overBudget => (
            FLucideIcons.triangleAlert,
            semantic.danger,
            l10n.fireBudgetOverTitle,
            l10n.fireBudgetOverDetail,
          ),
        };
        return Semantics(
          key: const ValueKey('fire-budget-posture'),
          container: true,
          label: '$title. $detail',
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s10,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: AppOpacity.whisper),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: color.withValues(alpha: AppOpacity.disabled),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: AppIconSizes.sm, color: color),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.labelStyle.copyWith(color: color),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(detail, style: context.captionStyle),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Projection is the only secondary story card on the main path.
class _ProjectionCard extends StatelessWidget {
  const _ProjectionCard({required this.view});

  final FireDashboardView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scenarios = view.scenarios;
    return SoftCard.raised(
      padding: AppPageRhythm.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.fireProjectionTitle, style: context.rowTitleStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(l10n.fireProjectionSubtitle, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s12),
          LayoutBuilder(
            builder: (context, c) => FireScenariosChart(
              scenarios: scenarios,
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
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
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
                '(${formatters.percent(s.annualReturn, decimalDigits: 1)})',
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

/// Stress + what-if simulations — off the critical path.
class _FireDepthSection extends StatefulWidget {
  const _FireDepthSection();

  @override
  State<_FireDepthSection> createState() => _FireDepthSectionState();
}

class _FireDepthSectionState extends State<_FireDepthSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard.raised(
          borderless: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: AppSpacing.s12,
          ),
          onPress: () {
            AppInteraction.signal(AppInteractionIntent.reveal);
            setState(() => _open = !_open);
          },
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.fireDepthTitle, style: context.rowTitleStyle),
                    const SizedBox(height: AppSpacing.s2),
                    Text(l10n.fireDepthSubtitle, style: context.captionStyle),
                  ],
                ),
              ),
              Icon(
                _open ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                size: AppIconSizes.md,
                color: colors.mutedForeground,
              ),
            ],
          ),
        ),
        AnimatedSizeFade(
          visible: _open,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: AppPageRhythm.module),
              FireStressTestsCard(),
              SizedBox(height: AppPageRhythm.module),
              FireSimulationsCard(),
            ],
          ),
        ),
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
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
        const SizedBox(width: AppSpacing.s4),
        Text(label, style: context.theme.typography.body.xs),
      ],
    );
  }
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
