part of 'health_today_page.dart';

/// Latest readings share units and calendar aggregation with Trends.
class _MetricGrid extends ConsumerStatefulWidget {
  const _MetricGrid();
  @override
  ConsumerState<_MetricGrid> createState() => _MetricGridState();
}

class _MetricGridState extends ConsumerState<_MetricGrid> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(healthTodayMetricGridProvider);
    final l = AppLocalizations.of(context);
    return async.when(
      loading: () => const SkeletonCard(child: SkeletonBox(height: 96)),
      error: (error, stack) => kDefaultError(
        context,
        error,
        stack,
        onRetry: () => ref.invalidate(healthTodaySnapshotProvider),
      ),
      data: (model) {
        final available = {
          HealthMetricKind.sleepSession,
          HealthMetricKind.hrvDaily,
          HealthMetricKind.rhrDaily,
          HealthMetricKind.stepsDaily,
          HealthMetricKind.weight,
          HealthMetricKind.bodyFat,
          ...HealthMetricKind.values,
        }.where((kind) => model.latest(kind) != null).toList();
        if (available.isEmpty) return const SizedBox.shrink();
        final primary = available.take(4).toList();
        final secondary = available.skip(4).toList();
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20
                ? 1
                : 2;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HealthSectionHeading(l.healthKeyMetrics),
                AppGroupedSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (
                        var start = 0;
                        start < primary.length;
                        start += columns
                      ) ...[
                        if (start > 0)
                          const AppGroupedDivider(
                            indent: AppSpacing.s16,
                            endIndent: AppSpacing.s16,
                          ),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                var offset = 0;
                                offset < columns;
                                offset++
                              ) ...[
                                if (offset > 0)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.s16,
                                    ),
                                    child: SizedBox(
                                      width: AppStroke.hairline,
                                      child: ColoredBox(
                                        color: context.theme.colors.border
                                            .withValues(
                                              alpha: AppOpacity.faint,
                                            ),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: start + offset < primary.length
                                      ? _TodayMetricCard(
                                          kind: primary[start + offset],
                                          model: model,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (secondary.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s8),
                  AppRevealControl(
                    expanded: _expanded,
                    collapsedLabel: l.commonRevealMore(secondary.length),
                    expandedLabel: l.commonRevealLess,
                    onToggle: () => setState(() => _expanded = !_expanded),
                  ),
                  AnimatedSizeFade(
                    visible: _expanded,
                    child: AppGroupedSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < secondary.length; i++) ...[
                            if (i > 0) const AppGroupedDivider(),
                            _TodayMetricCard(
                              kind: secondary[i],
                              model: model,
                              compact: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _TodayMetricCard extends StatelessWidget {
  const _TodayMetricCard({
    required this.kind,
    required this.model,
    this.compact = false,
  });
  final HealthMetricKind kind;
  final HealthTodayMetricGridModel model;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final row = model.latest(kind)!;
    final series = model.series[kind];
    final sample = series?.latest;
    final value = sample?.value ?? healthDisplayValue(row);
    final day = sample?.day ?? healthMetricDay(row);
    void open() => context.go(healthTrendPath(metricKind: kind));
    if (compact) {
      return AppTappable(
        onPress: open,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Row(
            children: [
              Icon(
                kind.icon,
                size: AppIconSizes.sm,
                color: context.appTheme.categorical.adapt(kind.accent),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind.title(l), style: context.rowTitleStyle),
                    Text(
                      healthDateLabel(l, day),
                      style: context.microCaptionStyle,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Text(
                  kind.formatValue(l, value),
                  style: context.strongTitleStyle,
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.xs,
                color: context.theme.colors.mutedForeground,
              ),
            ],
          ),
        ),
      );
    }
    return AppTappable(
      onPress: open,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIconTile(
                  icon: kind.icon,
                  size: AppSpacing.s28,
                  iconSize: AppIconSizes.sm,
                  radius: AppRadius.sm,
                  color: context.appTheme.categorical.adapt(kind.accent),
                  backgroundOpacity: AppOpacity.faint,
                  foregroundOpacity: 1,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(kind.title(l), style: context.captionStyle),
                ),
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.xs,
                  color: context.theme.colors.mutedForeground,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              kind.formatValue(l, value),
              style: context.appTheme.type.numericTitleStrong,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(healthDateLabel(l, day), style: context.microCaptionStyle),
          ],
        ),
      ),
    );
  }
}
