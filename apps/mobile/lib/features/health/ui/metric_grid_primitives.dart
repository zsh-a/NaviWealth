part of 'health_today_page.dart';

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
      padding: AppPageRhythm.cardPadding,
      onPress: trendKind == null
          ? null
          : () => context.go(healthTrendPath(metricKind: trendKind)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppMetricHeader(
            icon: icon,
            title: label,
            color: context.appTheme.categorical.adapt(accent),
            showChevron: trendKind != null,
          ),
          const SizedBox(height: AppPageRhythm.row),
          child,
        ],
      ),
    );
  }
}

class _ValueBig extends StatelessWidget {
  const _ValueBig({
    required this.value,
    required this.format,
    required this.sub,
    this.unit,
    this.trend,
    this.metric,
  });

  /// Numeric headline value — rolls via [AnimatedValueText] when it changes.
  final num value;

  /// Renders the (possibly interpolated) value, e.g. `(v) => '${v.round()}'`.
  final String Function(num value) format;
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
              child: AnimatedValueText(
                value: value,
                format: format,
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

/// Shared trend badge for metric tiles (regular and compact grids).
///
/// Renders through [DeltaText] so the direction color follows the user's
/// market-color preference (incl. colorblind mode) like every other delta
/// in the app, instead of the old hard-coded primary/destructive pair.
class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});
  final MetricTrend trend;

  @override
  Widget build(BuildContext context) {
    if (trend.direction == TrendDirection.flat) {
      return const SizedBox.shrink();
    }
    return DeltaText(
      value: trend.deltaPct,
      format: DeltaFormat.percent,
      fractionDigits: 0,
      style: context.captionLabelStyle,
      color: switch (trend.isFavorable) {
        true => context.appTheme.status.success.fg,
        false => context.appTheme.status.danger.fg,
        null => context.appTheme.status.info.fg,
      },
    );
  }
}

class _ValueDash extends StatelessWidget {
  const _ValueDash();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
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
        Text(l10n.healthNoData, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s2),
        Text(
          l10n.healthNoDataSyncHint,
          style: context.microCaptionStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
