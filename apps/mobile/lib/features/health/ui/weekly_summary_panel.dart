part of 'health_today_page.dart';

class _WeeklySummaryPanel extends ConsumerWidget {
  const _WeeklySummaryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(weeklySummaryProvider);
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return async.when(
      loading: () => const _WeeklySummarySkeleton(),
      error: (_, _) => const SizedBox.shrink(),
      data: (summary) {
        final stats = summary == null
            ? const <_WeeklyStat>[]
            : [
                _WeeklyStat(
                  icon: FLucideIcons.footprints,
                  value: Fmt.number(summary.totalSteps.round()),
                  label: l10n.healthStepsMetricLabel,
                  color: HealthMetricColors.steps,
                ),
                if (summary.avgSleepHours > 0)
                  _WeeklyStat(
                    icon: FLucideIcons.moon,
                    value: '${_round(summary.avgSleepHours)}h',
                    label: l10n.healthSleepMetricLabel,
                    color: HealthMetricColors.sleep,
                  ),
                if (summary.workoutCount > 0)
                  _WeeklyStat(
                    icon: FLucideIcons.dumbbell,
                    value: _formatWeeklyWorkoutValue(
                      l10n,
                      summary.totalWorkoutMinutes,
                      summary.workoutCount,
                    ),
                    label: l10n.healthWorkoutMetricLabel,
                    color: HealthMetricColors.workout,
                  ),
                if (summary.avgHrv > 0)
                  _WeeklyStat(
                    icon: FLucideIcons.heartPulse,
                    value: '${summary.avgHrv.round()}ms',
                    label: l10n.healthHrvMetricLabel,
                    color: HealthMetricColors.hrv,
                  ),
                if (summary.avgRhr > 0)
                  _WeeklyStat(
                    icon: FLucideIcons.heart,
                    value: '${summary.avgRhr.round()}bpm',
                    label: l10n.healthRhrMetricLabel,
                    color: HealthMetricColors.rhr,
                  ),
              ];
        return SoftCard(
          level: SoftCardLevel.raised,
          borderless: true,
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HealthPanelHeader(
                icon: FLucideIcons.calendarDays,
                title: l10n.healthWeeklySummaryTitle,
                subtitle: l10n.healthWeeklySummarySubtitle,
                color: colors.mutedForeground,
                trailing: const AppBadge(
                  label: '7d',
                  size: AppBadgeSize.compact,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              if (stats.isEmpty)
                _InlineEmptyState(
                  icon: FLucideIcons.activity,
                  message: l10n.healthWeeklySummaryEmpty,
                )
              else
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [
                    for (final stat in stats)
                      AppInfoChip(
                        icon: stat.icon,
                        value: stat.value,
                        label: stat.label,
                        color: stat.color,
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

String _formatWeeklyWorkoutValue(
  AppLocalizations l10n,
  int minutes,
  int count,
) {
  final duration = minutes >= 60
      ? l10n.healthWorkoutDurationHoursMinutes(minutes ~/ 60, minutes % 60)
      : l10n.healthWorkoutDurationMinutes(minutes);
  return l10n.healthWeeklyWorkoutValue(count, duration);
}

class _WeeklySummarySkeleton extends StatelessWidget {
  const _WeeklySummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      padding: EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 32, height: 32, radius: AppRadius.sm),
              SizedBox(width: AppSpacing.s8),
              Expanded(child: SkeletonBox(width: 140, height: 14)),
              SkeletonBox(width: 32, height: 18, radius: AppRadius.full),
            ],
          ),
          SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              SkeletonBox(width: 104, height: 42, radius: AppRadius.sm),
              SkeletonBox(width: 104, height: 42, radius: AppRadius.sm),
              SkeletonBox(width: 104, height: 42, radius: AppRadius.sm),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeeklyStat {
  const _WeeklyStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
}
