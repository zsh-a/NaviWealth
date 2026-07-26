part of 'health_today_page.dart';

/// Dual-density metrics: primary 2×2 hero cards, secondary as a quiet
/// compact list revealed with a light count control (not a full-width button).
class _MetricGrid extends ConsumerStatefulWidget {
  const _MetricGrid();

  @override
  ConsumerState<_MetricGrid> createState() => _MetricGridState();
}

class _MetricGridState extends ConsumerState<_MetricGrid> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final metrics = ref.watch(healthTodayMetricGridProvider);
    final l10n = AppLocalizations.of(context);

    AsyncValue<HealthMetric?> metric(
      HealthMetric? Function(HealthTodayMetricGridModel model) select,
    ) {
      if (metrics.hasValue) {
        return AsyncValue.data(select(metrics.requireValue));
      }
      if (metrics.hasError) {
        return AsyncValue.error(
          metrics.error!,
          metrics.stackTrace ?? StackTrace.current,
        );
      }
      return const AsyncValue.loading();
    }

    MetricTrend? trend(
      MetricTrend? Function(HealthTodayMetricGridModel model) select,
    ) {
      final model = metrics.value;
      return model == null ? null : select(model);
    }

    final secondaryRows = _secondaryRows(
      l10n: l10n,
      model: metrics.value,
      isLoading: metrics.isLoading && !metrics.hasValue,
    );

    // Collapse the 2×2 empty-card grid into one quiet surface when nothing
    // has been synced yet — empty SoftCards burn vertical space without signal.
    final model = metrics.value;
    final isLoading = metrics.isLoading && !metrics.hasValue;
    final primaryHasData =
        model != null &&
        (model.sleep != null ||
            model.hrv != null ||
            model.rhr != null ||
            model.steps != null);
    final showEmptyCluster = !isLoading && metrics.hasValue && !primaryHasData;

    if (showEmptyCluster) {
      return SoftCard.raised(
        borderless: true,
        padding: AppPageRhythm.cardPadding,
        child: AppEmptyState(
          icon: FLucideIcons.activity,
          title: l10n.healthNoData,
          message: l10n.healthNoDataSyncHint,
          compact: true,
          iconSize: AppIconSizes.lg,
        ),
      );
    }

    // Recovery-first primary quartet — only render cells that load or have data.
    final primary = <Widget>[
      if (isLoading || model?.sleep != null)
        _SleepCard(
          async: metric((m) => m.sleep),
          trend: trend((m) => m.sleepTrend),
        ),
      if (isLoading || model?.hrv != null)
        _HrvCard(async: metric((m) => m.hrv), trend: trend((m) => m.hrvTrend)),
      if (isLoading || model?.rhr != null)
        _RhrCard(async: metric((m) => m.rhr), trend: trend((m) => m.rhrTrend)),
      if (isLoading || model?.steps != null)
        _StepsCard(
          async: metric((m) => m.steps),
          trend: trend((m) => m.stepsTrend),
        ),
    ];

    // While loading with no cards yet, keep a compact skeleton grid.
    final displayPrimary = primary.isEmpty && isLoading
        ? <Widget>[
            _SleepCard(async: metric((m) => m.sleep)),
            _HrvCard(async: metric((m) => m.hrv)),
            _RhrCard(async: metric((m) => m.rhr)),
            _StepsCard(async: metric((m) => m.steps)),
          ]
        : primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= Breakpoints.contentThreeColumn
            ? 3
            : maxWidth < 360
            ? 1
            : 2;
        const gap = AppPageRhythm.row;
        final computedCardWidth = maxWidth.isFinite
            ? (maxWidth - gap * (columns - 1)) / columns
            : 220.0;
        final cardWidth = computedCardWidth < 0 ? 0.0 : computedCardWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (displayPrimary.isNotEmpty)
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final card in displayPrimary)
                    SizedBox(width: cardWidth, child: card),
                ],
              ),
            if (secondaryRows.isNotEmpty) ...[
              const SizedBox(height: AppPageRhythm.module),
              AppRevealControl(
                expanded: _expanded,
                collapsedLabel: l10n.commonRevealMore(secondaryRows.length),
                expandedLabel: l10n.commonRevealLess,
                onToggle: () => setState(() => _expanded = !_expanded),
              ),
              AnimatedSizeFade(
                visible: _expanded,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppPageRhythm.row),
                  child: AppGroupedSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < secondaryRows.length; i++) ...[
                          secondaryRows[i],
                          if (i != secondaryRows.length - 1)
                            const AppGroupedDivider(
                              indent: AppSpacing.s12,
                              endIndent: AppSpacing.s12,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Compact secondary metrics — only rows with real values (or loading
  /// placeholders while the grid is still resolving).
  List<Widget> _secondaryRows({
    required AppLocalizations l10n,
    required HealthTodayMetricGridModel? model,
    required bool isLoading,
  }) {
    if (isLoading) return const <Widget>[];
    if (model == null) return const <Widget>[];

    final rows = <Widget>[];

    void add({
      required HealthMetric? metric,
      required MetricTrend? trend,
      required IconData icon,
      required String label,
      required Color accent,
      required HealthMetricKind kind,
      required String Function(HealthMetric m) valueOf,
      String? Function(HealthMetric m)? unitOf,
    }) {
      if (metric == null) return;
      rows.add(
        _MetricCompactRow(
          icon: icon,
          label: label,
          accent: accent,
          value: valueOf(metric),
          unit: unitOf?.call(metric),
          trend: trend,
          onPress: () => context.go(healthTrendPath(metricKind: kind)),
        ),
      );
    }

    add(
      metric: model.bodyBattery,
      trend: model.bodyBatteryTrend,
      icon: FLucideIcons.battery,
      label: l10n.healthBodyBatteryMetricLabel,
      accent: HealthMetricColors.bodyBattery,
      kind: HealthMetricKind.bodyBatteryDaily,
      valueOf: (m) => '${m.value.round()}',
    );
    add(
      metric: model.stress,
      trend: model.stressTrend,
      icon: FLucideIcons.brain,
      label: l10n.healthStressMetricLabel,
      accent: HealthMetricColors.stress,
      kind: HealthMetricKind.stressDaily,
      valueOf: (m) => '${m.value.round()}',
    );
    add(
      metric: model.heartRate,
      trend: model.heartRateTrend,
      icon: FLucideIcons.heartPulse,
      label: l10n.healthHeartRateMetricLabel,
      accent: HealthMetricColors.heartRate,
      kind: HealthMetricKind.heartRateDaily,
      valueOf: (m) => '${_round(m.value)}',
      unitOf: (m) => m.unit.isEmpty ? null : m.unit,
    );
    add(
      metric: model.workout,
      trend: null,
      icon: FLucideIcons.dumbbell,
      label: l10n.healthWorkoutMetricLabel,
      accent: HealthMetricColors.workout,
      kind: HealthMetricKind.workoutSession,
      valueOf: (m) => '${(m.value / 60).round()}',
      unitOf: (_) => 'm',
    );
    add(
      metric: model.energy,
      trend: model.energyTrend,
      icon: FLucideIcons.flame,
      label: l10n.healthEnergyMetricLabel,
      accent: HealthMetricColors.totalEnergy,
      kind: HealthMetricKind.activeEnergyDaily,
      valueOf: (m) => '${m.value.round()}',
      unitOf: (_) => 'kcal',
    );
    add(
      metric: model.trainingLoad,
      trend: null,
      icon: FLucideIcons.activity,
      label: l10n.healthTrainingLoadMetricLabel,
      accent: HealthMetricColors.trainingLoad,
      kind: HealthMetricKind.trainingLoadDaily,
      valueOf: (m) => '${_round(m.value)}',
    );
    add(
      metric: model.spo2,
      trend: null,
      icon: FLucideIcons.wind,
      label: l10n.healthSpo2MetricLabel,
      accent: HealthMetricColors.spo2,
      kind: HealthMetricKind.spo2Daily,
      valueOf: (m) => '${_round(m.value)}',
      unitOf: (_) => '%',
    );

    return rows;
  }
}

/// Single-line secondary metric — flat density under primary cards.
class _MetricCompactRow extends StatelessWidget {
  const _MetricCompactRow({
    required this.icon,
    required this.label,
    required this.accent,
    required this.value,
    required this.onPress,
    this.unit,
    this.trend,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final String value;
  final String? unit;
  final MetricTrend? trend;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      label: '$label $value${unit == null ? '' : ' $unit'}',
      child: FTappable(
        onPress: onPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              AppIconTile(
                icon: icon,
                color: accent,
                size: 28,
                iconSize: AppIconSizes.sm,
                radius: AppRadius.sm,
                backgroundOpacity: AppOpacity.light,
                foregroundOpacity: 1,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text(
                  label,
                  style: context.rowTitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trend != null) ...[
                _TrendBadge(trend: trend!),
                const SizedBox(width: AppSpacing.s8),
              ],
              Text(value, style: context.strongTitleStyle),
              if (unit != null && unit!.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.s2),
                Text(unit!, style: context.captionMediumStyle),
              ],
              const SizedBox(width: AppSpacing.s6),
              Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.xs,
                color: colors.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
