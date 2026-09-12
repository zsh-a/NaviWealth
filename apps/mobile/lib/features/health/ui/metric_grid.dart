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
            final columns = constraints.maxWidth < 320 ? 1 : 2;
            final width =
                (constraints.maxWidth - AppSpacing.s8 * (columns - 1)) /
                columns;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [
                    for (final kind in primary)
                      SizedBox(
                        width: width,
                        child: _TodayMetricCard(kind: kind, model: model),
                      ),
                  ],
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
    final caption = [
      healthDateLabel(l, day),
      if (series != null && series.samples.length > 1) l.healthWindowShort(7),
    ].join(' · ');
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
    return SoftCard.raised(
      onPress: open,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppMetricHeader(
            icon: kind.icon,
            title: kind.title(l),
            color: context.appTheme.categorical.adapt(kind.accent),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(kind.formatValue(l, value), style: context.strongTitleStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(caption, style: context.microCaptionStyle),
          if (series != null &&
              series.samples.isNotEmpty &&
              kind != HealthMetricKind.trainingEffectDaily) ...[
            const SizedBox(height: AppSpacing.s8),
            SizedBox(
              height: AppSpacing.s32,
              child: HealthSeriesChart(series: series, compact: true),
            ),
          ],
        ],
      ),
    );
  }
}
