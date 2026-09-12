part of 'health_today_page.dart';

class _RecoveryHero extends ConsumerStatefulWidget {
  const _RecoveryHero();

  @override
  ConsumerState<_RecoveryHero> createState() => _RecoveryHeroState();
}

class _RecoveryHeroState extends ConsumerState<_RecoveryHero> {
  bool _showEvidence = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recoverySignalProvider);
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return AppCollapsingStage(
      child: SoftCard.hero(
        padding: AppPageRhythm.heroPadding,
        child: async.when(
          loading: () => const SizedBox(
            height: AppControlHeights.compactLoadingState,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 96, height: 12, radius: AppRadius.sm),
                SizedBox(height: AppSpacing.s8),
                SkeletonBox(width: 140, height: 28, radius: AppRadius.sm),
                SizedBox(height: AppSpacing.s8),
                SkeletonBox(width: 180, height: 12, radius: AppRadius.sm),
              ],
            ),
          ),
          error: (error, _) => AppEmptyState.error(
            title: l10n.commonLoadFailed,
            message: userSafeErrorMessage(
              context,
              error,
              operation: 'load recovery signal',
            ),
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(recoverySignalProvider),
            compact: true,
          ),
          data: (out) {
            final verdict = out?['verdict']?.toString() ?? 'insufficient_data';
            final score = out?['score'];
            final scoreValue = score is num ? score : null;
            final confidence = out?['confidence']?.toString() ?? 'insufficient';
            final coverage = (out?['coverage'] as num?)?.toDouble() ?? 0;
            final freshnessHours = (out?['freshness_hours'] as num?)
                ?.toDouble();
            final components = switch (out?['components']) {
              final List<Object?> values =>
                values
                    .whereType<Map<Object?, Object?>>()
                    .map(
                      (value) => value.map(
                        (key, value) => MapEntry(key.toString(), value),
                      ),
                    )
                    .toList(growable: false),
              _ => const <Map<String, Object?>>[],
            };
            final color = RecoveryVerdict.color(verdict, colors);
            final scoreColor =
                confidence == 'low' || confidence == 'insufficient'
                ? colors.mutedForeground
                : color;
            final actions = healthPlanActionsForVerdict(verdict, l10n);
            if (score == null ||
                confidence == 'insufficient' ||
                verdict == 'insufficient_data') {
              return _RecoveryInsufficientState(verdict: verdict, color: color);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIconTile(
                      icon: RecoveryVerdict.icon(verdict),
                      color: color,
                      size: 36,
                      iconSize: AppIconSizes.md,
                      backgroundOpacity: AppOpacity.medium,
                      foregroundOpacity: 1,
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      child: Text(
                        l10n.healthRecoveryTitle,
                        style: context.mutedLabelStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AnimatedValueText(
                      value: scoreValue,
                      format: (v) => '${v.round()}',
                      style: TypographyTokens.numericDisplay.copyWith(
                        color: scoreColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),
                Text(
                  RecoveryVerdict.label(verdict, l10n),
                  style: TypographyTokens.displaySmall.copyWith(
                    color: color,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  RecoveryVerdict.suggestion(verdict, l10n),
                  style: context.bodyCaptionStyle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s8),
                Wrap(
                  spacing: AppSpacing.s6,
                  runSpacing: AppSpacing.s6,
                  children: [
                    AppBadge(
                      label: l10n.healthRecoveryConfidence(
                        _confidenceLabel(confidence, l10n),
                        (coverage * 100).round(),
                      ),
                      size: AppBadgeSize.compact,
                    ),
                    if (freshnessHours != null && freshnessHours > 36)
                      AppBadge(
                        label: l10n.healthRecoveryFreshness(
                          _ago(
                            l10n,
                            DateTime.now().toUtc().subtract(
                              Duration(minutes: (freshnessHours * 60).round()),
                            ),
                          ),
                        ),
                        tone: AppBadgeTone.warning,
                        size: AppBadgeSize.compact,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                AppRevealControl(
                  expanded: _showEvidence,
                  collapsedLabel: l10n.healthRecoveryWhyTitle,
                  expandedLabel: l10n.healthRecoveryWhyLess,
                  onToggle: () =>
                      setState(() => _showEvidence = !_showEvidence),
                ),
                AnimatedSizeFade(
                  visible: _showEvidence,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final component in components) ...[
                        const SizedBox(height: AppSpacing.s8),
                        _RecoveryEvidenceRow(component: component),
                      ],
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s12),
                        Text(
                          l10n.healthPlanTodayActions,
                          style: context.microCaptionStyle,
                        ),
                        for (final action in actions) ...[
                          const SizedBox(height: AppSpacing.s8),
                          _PlanActionRow(action: action, color: colors.primary),
                        ],
                      ],
                      const SizedBox(height: AppSpacing.s12),
                      Text(
                        l10n.healthPlanDisclaimer,
                        style: context.microCaptionStyle,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RecoveryInsufficientState extends StatelessWidget {
  const _RecoveryInsufficientState({
    required this.verdict,
    required this.color,
  });

  final String verdict;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIconTile(
              icon: RecoveryVerdict.icon(verdict),
              color: color,
              size: 36,
              iconSize: AppIconSizes.md,
              backgroundOpacity: AppOpacity.medium,
              foregroundOpacity: 1,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(
                l10n.healthRecoveryTitle,
                style: context.mutedLabelStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        Text(
          RecoveryVerdict.label(verdict, l10n),
          style: context.labelStyle.copyWith(color: color),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          RecoveryVerdict.suggestion(verdict, l10n),
          style: context.bodyCaptionStyle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _RecoveryEvidenceRow extends StatelessWidget {
  const _RecoveryEvidenceRow({required this.component});

  final Map<String, Object?> component;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final metric = component['metric']?.toString() ?? '';
    final recent = (component['recent_value'] as num?)?.toDouble();
    final baseline = (component['baseline_value'] as num?)?.toDouble();
    final recentSamples = (component['recent_samples'] as num?)?.toInt();
    final baselineSamples = (component['baseline_samples'] as num?)?.toInt();
    final delta = (component['delta_pct'] as num?)?.toDouble();
    if (recent == null) return const SizedBox.shrink();
    final recentLabel = _recoveryValue(metric, recent);
    final message = delta == null
        ? l10n.healthRecoveryEvidenceNoBaseline(
            _recoveryMetricLabel(l10n, metric),
            recentLabel,
          )
        : l10n.healthRecoveryEvidence(
            _recoveryMetricLabel(l10n, metric),
            recentLabel,
            delta >= 0
                ? l10n.healthRecoveryDeltaUp(delta.abs().toStringAsFixed(1))
                : l10n.healthRecoveryDeltaDown(delta.abs().toStringAsFixed(1)),
          );
    final evidenceMeta = baseline != null
        ? l10n.healthRecoveryEvidenceBaseline(
            _recoveryValue(metric, baseline),
            recentSamples ?? 0,
            baselineSamples ?? 0,
          )
        : recentSamples == null
        ? null
        : l10n.healthRecoveryEvidenceNoBaselineSamples(recentSamples);
    final score = (component['score'] as num?)?.toDouble() ?? 50;
    final status = context.appTheme.status;
    final color = score >= 60
        ? status.success.fg
        : score < 40
        ? status.warning.fg
        : context.theme.colors.mutedForeground;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: AppSpacing.s6,
          height: AppSpacing.s6,
          margin: const EdgeInsets.only(top: AppSpacing.s6),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: context.captionStyle),
              if (evidenceMeta != null) ...[
                const SizedBox(height: AppSpacing.s2),
                Text(evidenceMeta, style: context.microCaptionStyle),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _recoveryMetricLabel(AppLocalizations l10n, String metric) =>
    switch (metric) {
      'hrv' => l10n.healthRecoveryMetricHrv,
      'rhr' => l10n.healthRecoveryMetricRhr,
      'sleep' => l10n.healthRecoveryMetricSleep,
      'vo2_max' => l10n.healthRecoveryMetricVo2,
      'body_battery' => l10n.healthRecoveryMetricBodyBattery,
      'stress' => l10n.healthRecoveryMetricStress,
      _ => metric,
    };

String _recoveryValue(String metric, double value) => switch (metric) {
  'hrv' => '${value.toStringAsFixed(1)} ms',
  'rhr' => '${value.toStringAsFixed(1)} bpm',
  'sleep' => '${value.toStringAsFixed(1)} h',
  'vo2_max' => value.toStringAsFixed(1),
  'body_battery' || 'stress' => '${value.toStringAsFixed(0)}/100',
  _ => value.toStringAsFixed(1),
};

String _confidenceLabel(String confidence, AppLocalizations l10n) =>
    switch (confidence) {
      'high' => l10n.healthRecoveryConfidenceHigh,
      'medium' => l10n.healthRecoveryConfidenceMedium,
      'low' => l10n.healthRecoveryConfidenceLow,
      _ => l10n.healthRecoveryConfidenceInsufficient,
    };

class _PlanActionRow extends StatelessWidget {
  const _PlanActionRow({required this.action, required this.color});

  final HealthPlanAction action;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIconTile(
          icon: action.icon,
          color: color,
          size: 28,
          iconSize: AppIconSizes.sm,
          radius: AppRadius.sm,
          backgroundOpacity: AppOpacity.light,
          foregroundOpacity: 1,
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: Text(
              action.text,
              style: context.theme.typography.body.sm,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
