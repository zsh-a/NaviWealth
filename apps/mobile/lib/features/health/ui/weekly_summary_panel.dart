part of 'health_today_page.dart';

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
    return artifactAsync.when(
      loading: () => const _WeeklySummarySkeleton(),
      error: (error, _) => _WeeklySummaryFallback(
        async: async,
        runAsync: runAsync,
        agentLoadError: error,
      ),
      data: (artifact) {
        if (artifact != null) {
          final run = runAsync.value;
          if (run != null &&
              agent_result_providers.AgentResultBundle.shouldPrioritizeRun(
                run,
                artifact,
              )) {
            return _WeeklySummaryFallback(async: async, runAsync: runAsync);
          }
          return _WeeklySummaryArtifactCard(
            artifact: artifact,
            onVisibilityChanged: () {
              ref.invalidate(
                health_agent_providers.latestHealthReviewAgentResultsProvider,
              );
            },
          );
        }
        return _WeeklySummaryFallback(async: async, runAsync: runAsync);
      },
    );
  }
}

class _WeeklySummaryArtifactCard extends StatelessWidget {
  const _WeeklySummaryArtifactCard({
    required this.artifact,
    required this.onVisibilityChanged,
  });

  final AgentArtifact artifact;
  final VoidCallback onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final metaLabel = l10n.healthBriefingUpdated(
      _ago(l10n, artifact.createdAt),
    );

    void openArtifact() {
      showAgentArtifactSheet(
        context: context,
        artifact: artifact,
        subtitle: l10n.healthWeeklySummarySubtitle,
        onVisibilityChanged: onVisibilityChanged,
      );
    }

    return AgentResultCard(
      artifact: artifact,
      metaLabel: metaLabel,
      layout: AgentResultCardLayout.summary,
      onOpen: openArtifact,
    );
  }
}

class _WeeklySummaryFallback extends ConsumerWidget {
  const _WeeklySummaryFallback({
    required this.async,
    required this.runAsync,
    this.agentLoadError,
  });

  final AsyncValue<WeeklySummary?> async;
  final AsyncValue<AgentRunRecord?> runAsync;
  final Object? agentLoadError;

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
    final agentLoadError = this.agentLoadError;
    if (agentLoadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentResultPanelStateCard(
            icon: FLucideIcons.triangleAlert,
            title: l10n.commonError,
            message: userSafeErrorMessage(context, agentLoadError),
            error: true,
            onRetry: () => ref.invalidate(
              health_agent_providers.latestHealthReviewAgentResultsProvider,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _WeeklySummaryMetricsCard(async: async),
        ],
      );
    }
    if (runAsync.isLoading && !runAsync.hasValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentResultPanelStateCard(
            icon: FLucideIcons.loaderCircle,
            title: l10n.commonLoading,
            message: l10n.agentResultLoadingBody,
            loading: true,
          ),
          const SizedBox(height: AppSpacing.s12),
          _WeeklySummaryMetricsCard(async: async),
        ],
      );
    }
    if (runAsync.hasError && !runAsync.hasValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentResultPanelStateCard(
            icon: FLucideIcons.triangleAlert,
            title: l10n.commonError,
            message: userSafeErrorMessage(context, runAsync.error!),
            error: true,
            onRetry: () => ref.invalidate(
              health_agent_providers.latestHealthReviewAgentResultsProvider,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _WeeklySummaryMetricsCard(async: async),
        ],
      );
    }
    final run = runAsync.value;
    if (run == null) return _WeeklySummaryMetricsCard(async: async);
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
