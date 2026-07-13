part of 'health_today_page.dart';

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

    // Recovery-first order: sleep → HRV → RHR → steps, then the rest.
    final cards = <Widget>[
      _SleepCard(
        async: metric((m) => m.sleep),
        trend: trend((m) => m.sleepTrend),
      ),
      _HrvCard(async: metric((m) => m.hrv), trend: trend((m) => m.hrvTrend)),
      _RhrCard(async: metric((m) => m.rhr), trend: trend((m) => m.rhrTrend)),
      _StepsCard(
        async: metric((m) => m.steps),
        trend: trend((m) => m.stepsTrend),
      ),
      _BodyBatteryCard(
        async: metric((m) => m.bodyBattery),
        trend: trend((m) => m.bodyBatteryTrend),
      ),
      _StressCard(
        async: metric((m) => m.stress),
        trend: trend((m) => m.stressTrend),
      ),
      _HeartRateCard(
        async: metric((m) => m.heartRate),
        trend: trend((m) => m.heartRateTrend),
      ),
      _WorkoutCard(async: metric((m) => m.workout)),
      _ActiveEnergyCard(
        async: metric((m) => m.energy),
        trend: trend((m) => m.energyTrend),
      ),
      _TrainingLoadCard(async: metric((m) => m.trainingLoad)),
      _Spo2Card(async: metric((m) => m.spo2)),
    ];
    final visibleCards = _expanded ? cards : cards.take(4).toList();
    final l10n = AppLocalizations.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= Breakpoints.contentThreeColumn
            ? 3
            : maxWidth < 360
            ? 1
            : 2;
        const gap = AppSpacing.s8;
        final computedCardWidth = maxWidth.isFinite
            ? (maxWidth - gap * (columns - 1)) / columns
            : 220.0;
        final cardWidth = computedCardWidth < 0 ? 0.0 : computedCardWidth;
        return Column(
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in visibleCards)
                  SizedBox(width: cardWidth, child: card),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            SizedBox(
              width: double.infinity,
              child: AppQuietButton(
                label: _expanded
                    ? l10n.healthShowKeyMetrics
                    : l10n.healthShowAllMetrics,
                onPress: () => setState(() => _expanded = !_expanded),
                expanded: true,
                prefix: Icon(
                  _expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                  size: AppIconSizes.sm,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
