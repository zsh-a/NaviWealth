part of 'health_today_page.dart';

/// Weekly summary — signal only. Loading shells and empty weeks stay off
/// the Today surface so secondary depth does not compete with recovery.
class _WeeklySummaryPanel extends ConsumerWidget {
  const _WeeklySummaryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artifactAsync = ref.watch(
      health_agent_providers.latestWeeklySummaryArtifactProvider,
    );
    final runAsync = ref.watch(
      health_agent_providers.latestWeeklySummaryRunProvider,
    );
    final async = ref.watch(weeklySummaryProvider);

    // Quiet while still resolving — no skeleton on Today.
    if (artifactAsync.isLoading && !artifactAsync.hasValue) {
      return const SizedBox.shrink();
    }

    if (artifactAsync.hasError && !artifactAsync.hasValue) {
      return AgentResultPanelStateCard(
        icon: FLucideIcons.triangleAlert,
        title: AppLocalizations.of(context).commonError,
        message: userSafeErrorMessage(context, artifactAsync.error!),
        error: true,
        onRetry: () => ref.invalidate(
          health_agent_providers.latestWeeklySummaryArtifactProvider,
        ),
      );
    }

    final artifact = artifactAsync.value;
    if (artifact != null) {
      return _WeeklySummaryArtifactCard(
        artifact: artifact,
        run: runAsync.value,
        onVisibilityChanged: () {
          ref.invalidate(
            health_agent_providers.latestHealthReviewAgentResultsProvider,
          );
        },
        onRetry: () => _retryWeekly(ref),
      );
    }

    return _WeeklySummaryFallback(async: async, runAsync: runAsync);
  }
}

Future<void> _retryWeekly(WidgetRef ref) async {
  final controller = await ref.read(agentRunControllerProvider.future);
  await controller.runOnceById(kWeeklySummaryAgentId);
  ref.invalidate(health_agent_providers.latestHealthReviewAgentResultsProvider);
}

class _WeeklySummaryArtifactCard extends StatelessWidget {
  const _WeeklySummaryArtifactCard({
    required this.artifact,
    this.run,
    required this.onVisibilityChanged,
    this.onRetry,
  });

  final AgentArtifact artifact;
  final AgentRunRecord? run;
  final VoidCallback onVisibilityChanged;
  final FutureOr<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final metaLabel = l10n.healthBriefingUpdated(
      _ago(l10n, artifact.createdAt),
    );

    return AgentResultSurface(
      artifact: artifact,
      run: run,
      metaLabel: metaLabel,
      layout: AgentResultCardLayout.summary,
      summaryMaxLines: 5,
      onRetry: onRetry,
      onOpen: () => context.push(AgentArtifactRoutes.detail(artifact.id)),
    );
  }
}

class _WeeklySummaryFallback extends ConsumerWidget {
  const _WeeklySummaryFallback({required this.async, required this.runAsync});

  final AsyncValue<WeeklySummary?> async;
  final AsyncValue<AgentRunRecord?> runAsync;

  Future<void> _retry(WidgetRef ref) async {
    final controller = await ref.read(agentRunControllerProvider.future);
    await controller.runOnceById(kWeeklySummaryAgentId);
    ref.invalidate(
      health_agent_providers.latestHealthReviewAgentResultsProvider,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // Never paint a loading shell for the weekly agent on Today.
    if (runAsync.isLoading && !runAsync.hasValue) {
      return _WeeklySummaryMetricsCard(async: async);
    }
    if (runAsync.hasError && !runAsync.hasValue) {
      return AgentResultPanelStateCard(
        icon: FLucideIcons.triangleAlert,
        title: l10n.commonError,
        message: userSafeErrorMessage(context, runAsync.error!),
        error: true,
        onRetry: () => ref.invalidate(
          health_agent_providers.latestHealthReviewAgentResultsProvider,
        ),
      );
    }
    final run = runAsync.value;
    final showRun =
        run != null &&
        (run.status == AgentRunLifecycleStatus.running ||
            run.status == AgentRunLifecycleStatus.failed);
    if (!showRun) return _WeeklySummaryMetricsCard(async: async);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgentRunStatusCard(
          record: run,
          metaLabel: l10n.healthBriefingUpdated(_ago(l10n, run.startedAt)),
          onRetry: () => _retry(ref),
        ),
        const SizedBox(height: AppSpacing.s12),
        _WeeklySummaryMetricsCard(async: async),
      ],
    );
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
        if (stats.isEmpty) return const SizedBox.shrink();
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
