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

    final cards = <Widget>[
      _SleepCard(
        async: metric((m) => m.sleep),
        trend: trend((m) => m.sleepTrend),
      ),
      _BodyBatteryCard(
        async: metric((m) => m.bodyBattery),
        trend: trend((m) => m.bodyBatteryTrend),
      ),
      _StressCard(
        async: metric((m) => m.stress),
        trend: trend((m) => m.stressTrend),
      ),
      _HrvCard(async: metric((m) => m.hrv), trend: trend((m) => m.hrvTrend)),
      _HeartRateCard(
        async: metric((m) => m.heartRate),
        trend: trend((m) => m.heartRateTrend),
      ),
      _RhrCard(async: metric((m) => m.rhr), trend: trend((m) => m.rhrTrend)),
      _StepsCard(
        async: metric((m) => m.steps),
        trend: trend((m) => m.stepsTrend),
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

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.moon,
      label: l10n.healthSleepMetricLabel,
      trendKind: HealthMetricKind.sleepSession,
      accent: HealthMetricColors.sleep,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          final hours = _secondsToHours(m.value, m.unit);
          final stages = _parseSleepStages(m.payloadJson);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ValueBig(
                value: '${_round(hours)}',
                unit: 'h',
                sub: _ago(l10n, m.capturedAt),
                trend: trend,
                metric: m,
              ),
              if (stages != null) ...[
                const SizedBox(height: AppSpacing.s4),
                _SleepStageBar(
                  deepSeconds: stages.deep,
                  remSeconds: stages.rem,
                  lightSeconds: stages.light,
                  awakeSeconds: stages.awake,
                  totalSeconds: m.value,
                  l10n: l10n,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Parsed sleep stage durations from payloadJson.
class _SleepStages {
  const _SleepStages({
    required this.deep,
    required this.rem,
    required this.light,
    this.awake = 0,
  });
  final double deep;
  final double rem;
  final double light;
  final double awake;
}

_SleepStages? _parseSleepStages(String? payloadJson) {
  if (payloadJson == null || payloadJson.isEmpty) return null;
  try {
    final json = jsonDecode(payloadJson) as Map<String, dynamic>;
    // Support both short keys (Garmin + HealthKit) and legacy long keys.
    final deep =
        ((json['deep'] ?? json['deepSleepSeconds']) as num?)?.toDouble() ?? 0;
    final rem =
        ((json['rem'] ?? json['remSleepSeconds']) as num?)?.toDouble() ?? 0;
    final light =
        ((json['light'] ?? json['lightSleepSeconds']) as num?)?.toDouble() ?? 0;
    final awake =
        ((json['awake'] ?? json['awakeSleepSeconds']) as num?)?.toDouble() ?? 0;
    if (deep == 0 && rem == 0 && light == 0) return null;
    return _SleepStages(deep: deep, rem: rem, light: light, awake: awake);
  } catch (_) {
    return null;
  }
}

/// Compact horizontal bar showing deep/REM/light/awake proportions.
class _SleepStageBar extends StatelessWidget {
  const _SleepStageBar({
    required this.deepSeconds,
    required this.remSeconds,
    required this.lightSeconds,
    required this.awakeSeconds,
    required this.totalSeconds,
    required this.l10n,
  });

  final double deepSeconds;
  final double remSeconds;
  final double lightSeconds;
  final double awakeSeconds;
  final double totalSeconds;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    if (totalSeconds <= 0) return const SizedBox.shrink();

    final deepPct = deepSeconds / totalSeconds;
    final remPct = remSeconds / totalSeconds;
    final awakePct = awakeSeconds / totalSeconds;

    return Semantics(
      label: [
        '${l10n.healthSleepDeepLabel} ${_round(deepSeconds / 3600.0)}h',
        '${l10n.healthSleepRemLabel} ${_round(remSeconds / 3600.0)}h',
        '${l10n.healthSleepLightLabel} ${_round(lightSeconds / 3600.0)}h',
        if (awakeSeconds > 0)
          '${l10n.healthSleepAwakeLabel} ${_round(awakeSeconds / 3600.0)}h',
      ].join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: SizedBox(
              height: AppSpacing.s4,
              child: Row(
                children: [
                  if (deepPct > 0)
                    Expanded(
                      flex: (deepPct * 100).round().clamp(1, 100),
                      child: Container(color: colors.primary),
                    ),
                  if (remPct > 0)
                    Expanded(
                      flex: (remPct * 100).round().clamp(1, 100),
                      child: Container(
                        color: colors.primary.withValues(
                          alpha: AppOpacity.prominent,
                        ),
                      ),
                    ),
                  if (awakePct > 0)
                    Expanded(
                      flex: (awakePct * 100).round().clamp(1, 100),
                      child: Container(
                        color: colors.destructive.withValues(
                          alpha: AppOpacity.muted,
                        ),
                      ),
                    ),
                  Expanded(
                    flex: ((1 - deepPct - remPct - awakePct) * 100)
                        .round()
                        .clamp(1, 100),
                    child: Container(color: colors.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Wrap(
            spacing: AppSpacing.s6,
            runSpacing: AppSpacing.s2,
            children: [
              _stageChip(
                context,
                colors.primary,
                l10n.healthSleepDeepLabel,
                deepSeconds,
              ),
              _stageChip(
                context,
                colors.primary.withValues(alpha: AppOpacity.prominent),
                l10n.healthSleepRemLabel,
                remSeconds,
              ),
              _stageChip(
                context,
                colors.mutedForeground,
                l10n.healthSleepLightLabel,
                lightSeconds,
              ),
              if (awakeSeconds > 0)
                _stageChip(
                  context,
                  colors.destructive.withValues(alpha: AppOpacity.prominent),
                  l10n.healthSleepAwakeLabel,
                  awakeSeconds,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stageChip(
    BuildContext context,
    Color color,
    String label,
    double seconds,
  ) {
    final hours = seconds / 3600.0;
    return Text(
      '$label ${_round(hours)}h',
      style: context.captionStyle.copyWith(color: color),
    );
  }
}

class _HrvCard extends StatelessWidget {
  const _HrvCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.heartPulse,
      label: l10n.healthHrvMetricLabel,
      trendKind: HealthMetricKind.hrvDaily,
      accent: HealthMetricColors.hrv,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)}',
            unit: m.unit,
            sub: _ago(l10n, m.capturedAt),
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.heartPulse,
      label: l10n.healthHeartRateMetricLabel,
      trendKind: HealthMetricKind.heartRateDaily,
      accent: HealthMetricColors.heartRate,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)}',
            unit: m.unit,
            sub: _ago(l10n, m.capturedAt),
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.dumbbell,
      label: l10n.healthWorkoutMetricLabel,
      trendKind: HealthMetricKind.workoutSession,
      accent: HealthMetricColors.workout,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          final minutes = (m.value / 60).round();
          final payload = _parseJsonMap(m.payloadJson);
          final distMeters = (payload['totalDistanceMeters'] as num?)
              ?.toDouble();
          final cal = (payload['totalEnergyKcal'] as num?)?.toDouble();
          final parts = <String>[];
          if (distMeters != null && distMeters > 0) {
            parts.add('${_round(distMeters / 1000)}km');
          }
          if (cal != null && cal > 0) {
            parts.add('${cal.round()}kcal');
          }
          final detail = parts.isEmpty ? '' : '${parts.join(' · ')} · ';
          return _ValueBig(
            value: '$minutes',
            unit: 'm',
            sub: '$detail${_ago(l10n, m.capturedAt)}',
            metric: m,
          );
        },
      ),
    );
  }
}

class _StepsCard extends ConsumerWidget {
  const _StepsCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final walking = ref.watch(latestWalkingDistanceProvider);
    return _MetricCard(
      icon: FLucideIcons.footprints,
      trendKind: HealthMetricKind.stepsDaily,
      label: l10n.healthStepsMetricLabel,
      accent: HealthMetricColors.steps,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          // Pair the distance line with steps when both refer to the
          // same UTC day; otherwise fall back to the time-ago line so
          // we don't show a stale-day distance next to today's steps.
          final stepsDay = _utcDayKey(m.capturedAt);
          final wm = walking.asData?.value;
          final sub = wm != null && _utcDayKey(wm.capturedAt) == stepsDay
              ? '${(wm.value / 1000.0).toStringAsFixed(1)} km · ${_ago(l10n, m.capturedAt)}'
              : _ago(l10n, m.capturedAt);
          return _ValueBig(
            value: _formatSteps(m.value),
            sub: sub,
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _ActiveEnergyCard extends StatelessWidget {
  const _ActiveEnergyCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.flame,
      label: l10n.healthEnergyMetricLabel,
      trendKind: HealthMetricKind.activeEnergyDaily,
      accent: HealthMetricColors.totalEnergy,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${m.value.round()}',
            unit: 'kcal',
            sub: _ago(l10n, m.capturedAt),
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _BodyBatteryCard extends StatelessWidget {
  const _BodyBatteryCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.battery,
      label: l10n.healthBodyBatteryMetricLabel,
      trendKind: HealthMetricKind.bodyBatteryDaily,
      accent: HealthMetricColors.bodyBattery,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          final payload = _parseJsonMap(m.payloadJson);
          final charged = (payload['charged'] as num?)?.toInt() ?? 0;
          final drained = (payload['drained'] as num?)?.toInt() ?? 0;
          final net = charged - drained;
          final netStr = net >= 0 ? '+$net' : '$net';
          return _ValueBig(
            value: '${m.value.round()}',
            sub: '$netStr · ${_ago(l10n, m.capturedAt)}',
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _StressCard extends StatelessWidget {
  const _StressCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.brain,
      trendKind: HealthMetricKind.stressDaily,
      label: l10n.healthStressMetricLabel,
      accent: HealthMetricColors.stress,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${m.value.round()}',
            sub: _ago(l10n, m.capturedAt),
            metric: m,
          );
        },
      ),
    );
  }
}

class _RhrCard extends StatelessWidget {
  const _RhrCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.heart,
      trendKind: HealthMetricKind.rhrDaily,
      label: l10n.healthRhrMetricLabel,
      accent: HealthMetricColors.rhr,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${m.value.round()}',
            sub: _ago(l10n, m.capturedAt),
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _TrainingLoadCard extends StatelessWidget {
  const _TrainingLoadCard({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.flame,
      label: l10n.healthTrainingLoadMetricLabel,
      trendKind: HealthMetricKind.trainingLoadDaily,
      accent: HealthMetricColors.trainingLoad,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)}',
            sub: _ago(l10n, m.capturedAt),
            metric: m,
          );
        },
      ),
    );
  }
}

class _Spo2Card extends StatelessWidget {
  const _Spo2Card({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.wind,
      trendKind: HealthMetricKind.spo2Daily,
      label: l10n.healthSpo2MetricLabel,
      accent: HealthMetricColors.spo2,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)}',
            unit: '%',
            sub: _ago(l10n, m.capturedAt),
            metric: m,
          );
        },
      ),
    );
  }
}

class _MetricCard extends ConsumerWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.child,
    required this.accent,
    this.trendKind,
  });
  final IconData icon;
  final String label;
  final Widget child;
  final Color accent;
  final HealthMetricKind? trendKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      onPress: trendKind == null
          ? null
          : () => context.go(healthTrendPath(metricKind: trendKind)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetricCardHeader(
              icon: icon,
              title: label,
              color: accent,
              showChevron: trendKind != null,
            ),
            const SizedBox(height: AppSpacing.s12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricCardHeader extends StatelessWidget {
  const _MetricCardHeader({
    required this.icon,
    required this.title,
    required this.color,
    required this.showChevron,
  });

  final IconData icon;
  final String title;
  final Color color;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      children: [
        AppIconTile(icon: icon, color: color),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            title,
            style: context.mutedLabelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showChevron)
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.h18,
            color: colors.mutedForeground.withValues(
              alpha: AppOpacity.disabled,
            ),
          ),
      ],
    );
  }
}

class _ValueBig extends StatelessWidget {
  const _ValueBig({
    required this.value,
    required this.sub,
    this.unit,
    this.trend,
    this.metric,
  });
  final String value;
  final String sub;
  final String? unit;
  final MetricTrend? trend;
  final HealthMetric? metric;

  @override
  Widget build(BuildContext context) {
    final source = metric == null ? null : sourceForHealthMetric(metric!);
    final sourceLabel = source == null || source == HealthMetricSource.unknown
        ? null
        : source.label;
    final hasMeta = trend != null || sourceLabel != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Line 1: value + unit inline (unit smaller).
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.strongTitleStyle,
              ),
            ),
            if (unit != null && unit!.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.s2),
              Text(unit!, style: context.captionMediumStyle),
            ],
          ],
        ),
        // Line 2: trend + source chip (if any).
        if (hasMeta) ...[
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: [
              if (trend != null) _TrendBadge(trend: trend!),
              if (trend != null && sourceLabel != null)
                const SizedBox(width: AppSpacing.s6),
              if (sourceLabel != null) _SourceChip(label: sourceLabel),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.s2),
        Text(sub, style: context.captionStyle),
      ],
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: AppBadge(label: label, size: AppBadgeSize.compact),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});
  final MetricTrend trend;

  @override
  Widget build(BuildContext context) {
    final dir = trend.direction;
    if (dir == TrendDirection.flat) return const SizedBox.shrink();
    final colors = context.theme.colors;
    final isUp = dir == TrendDirection.up;
    final color = isUp ? colors.primary : colors.destructive;
    final arrow = isUp ? '↑' : '↓';
    final pct = trend.deltaPct.abs().round();
    return Text(
      '$arrow$pct%',
      style: context.captionLabelStyle.copyWith(color: color),
    );
  }
}

class _ValueDash extends StatelessWidget {
  const _ValueDash();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '—',
          style: context.strongTitleStyle.copyWith(
            color: colors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          AppLocalizations.of(context).healthNoData,
          style: context.captionStyle,
        ),
      ],
    );
  }
}

class _ValueSkeleton extends StatelessWidget {
  const _ValueSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 56, height: 20),
        SizedBox(height: AppSpacing.s6),
        SkeletonBox(width: 40, height: 10),
      ],
    );
  }
}

double _secondsToHours(double value, String unit) => switch (unit) {
  's' => value / 3600.0,
  'min' => value / 60.0,
  'h' => value,
  _ => value / 3600.0,
};

double _round(double v) => (v * 100).round() / 100.0;

Map<String, dynamic> _parseJsonMap(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    return jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    return const {};
  }
}

String _utcDayKey(DateTime t) => AppFormatters.utcDayKey(t);

String _formatSteps(double v) => Fmt.number(v.round());

String _ago(AppLocalizations l10n, DateTime when) => AppFormatters.relativeTime(
  when,
  justNow: l10n.aiChatRelativeJustNow,
  minutesAgo: l10n.aiChatRelativeMinutesAgo,
  hoursAgo: l10n.aiChatRelativeHoursAgo,
  daysAgo: l10n.aiChatRelativeDaysAgo,
  dateFallback: (d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$mm-$dd';
  },
);
