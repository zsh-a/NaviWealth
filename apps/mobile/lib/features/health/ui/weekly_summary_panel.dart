part of 'health_today_page.dart';

/// Weekly digest. The deterministic metrics are the single presentation;
/// Agent run state and a second prose artifact no longer replace this view.
class _WeeklySummaryPanel extends ConsumerWidget {
  const _WeeklySummaryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _WeeklySummaryMetricsCard(async: ref.watch(weeklySummaryProvider));
  }
}

class _WeeklySummaryMetricsCard extends StatelessWidget {
  const _WeeklySummaryMetricsCard({required this.async});

  final AsyncValue<WeeklySummary?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return async.when(
      // loading: intentionally empty — empty weeks stay off Today, so this
      // card may never render; a skeleton would flash for a hidden section.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (summary) {
        if (summary == null) return const SizedBox.shrink();
        final stats = <_WeeklyStat>[
          if (summary.totalSteps > 0)
            _WeeklyStat(
              icon: FLucideIcons.footprints,
              value: HealthMetricKind.stepsDaily.formatValue(
                l10n,
                summary.totalSteps,
              ),
              label: l10n.healthStepsMetricLabel,
              color: HealthMetricColors.steps,
            ),
          if (summary.avgSleepHours > 0)
            _WeeklyStat(
              icon: FLucideIcons.moon,
              value: HealthMetricKind.sleepSession.formatValue(
                l10n,
                summary.avgSleepHours,
              ),
              label:
                  '${l10n.healthSleepMetricLabel} · ${l10n.healthAverageShort}',
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
              value: HealthMetricKind.hrvDaily.formatValue(
                l10n,
                summary.avgHrv,
              ),
              label:
                  '${l10n.healthHrvMetricLabel} · ${l10n.healthAverageShort}',
              color: HealthMetricColors.hrv,
            ),
          if (summary.avgRhr > 0)
            _WeeklyStat(
              icon: FLucideIcons.heart,
              value: HealthMetricKind.rhrDaily.formatValue(
                l10n,
                summary.avgRhr,
              ),
              label:
                  '${l10n.healthRhrMetricLabel} · ${l10n.healthAverageShort}',
              color: HealthMetricColors.rhr,
            ),
        ];
        if (stats.isEmpty) return const SizedBox.shrink();
        return SoftCard(
          onPress: () => context.go(healthTrendPath(windowDays: 7)),
          level: SoftCardLevel.raised,
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppMetricHeader(
                icon: FLucideIcons.calendarDays,
                title: l10n.healthWeeklySummaryTitle,
                color: colors.mutedForeground,
              ),
              const SizedBox(height: AppSpacing.s12),
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  for (final stat in stats)
                    AppInfoChip(
                      icon: stat.icon,
                      value: stat.value,
                      label: stat.label,
                      color: context.appTheme.categorical.adapt(stat.color),
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
