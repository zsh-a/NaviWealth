part of 'health_trend_page.dart';

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.spec, required this.points});

  final _TrendSpec spec;
  final AsyncValue<List<ChartPoint>?> points;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final accent = switch (spec.color) {
      null => colors.primary,
      final seed => context.appTheme.categorical.adapt(seed),
    };
    return SoftCard(
      key: ValueKey('health-trend-${spec.kind.name}'),
      level: SoftCardLevel.raised,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: spec.icon ?? FLucideIcons.activity,
                color: accent,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  spec.title,
                  style: context.mutedLabelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              points.when(
                // Matches the latest-value readout footprint so the header
                // row does not jump when the number lands.
                loading: () => const SkeletonBox(width: 56, height: 20),
                error: (_, _) => const SizedBox.shrink(),
                data: (pts) {
                  if (pts == null || pts.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final last = pts.last.y;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: AppSpacing.s6,
                        height: AppSpacing.s6,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: AppOpacity.strong),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s6),
                      Text(
                        _formatLatest(last, spec.kind),
                        style: context.strongRowTitleStyle.copyWith(
                          color: colors.foreground,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          if (spec.subtitle.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(
              spec.subtitle,
              style: context.captionStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          SizedBox(
            height: AppChartHeights.standard,
            child: points.when(
              loading: () => const Center(child: FCircularProgress()),
              error: (e, _) => Center(
                child: Text(
                  AppLocalizations.of(context).healthTrendLoadFailed(''),
                  style: context.captionStyle.copyWith(
                    color: colors.destructive,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              data: (pts) {
                if (pts == null || pts.length < 2) {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context).healthTrendNotEnoughData,
                      style: context.captionStyle,
                    ),
                  );
                }
                return NwLineChart(
                  filled: true,
                  heroDots: true,
                  series: <ChartSeries>[
                    ChartSeries(
                      name: spec.title,
                      points: pts,
                      colorOverride: accent,
                      strokeWidth: AppStroke.branch,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Format the latest chart value for display in the header.
  static String _formatLatest(double value, HealthMetricKind kind) {
    return switch (kind) {
      HealthMetricKind.sleepSession => '${(value * 10).round() / 10}h',
      HealthMetricKind.distanceWalkingRunningDaily =>
        '${(value * 10).round() / 10}km',
      HealthMetricKind.workoutSession => '${value.round()}m',
      HealthMetricKind.stepsDaily => _formatSteps(value),
      HealthMetricKind.weight ||
      HealthMetricKind.bodyFat => '${(value * 10).round() / 10}',
      _ => value.round().toString(),
    };
  }

  static String _formatSteps(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.round().toString();
  }
}
