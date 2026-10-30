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
            if (scoreValue == null ||
                confidence == 'insufficient' ||
                verdict == 'insufficient_data') {
              return _RecoveryInsufficientState(
                verdict: verdict,
                color: color,
                components: components,
                expanded: _showEvidence,
                onToggle: () => setState(() => _showEvidence = !_showEvidence),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    final summary = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.healthRecoveryTitle,
                          style: context.captionMediumStyle,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Row(
                          children: [
                            Icon(
                              RecoveryVerdict.icon(verdict),
                              size: AppIconSizes.md,
                              color: color,
                            ),
                            const SizedBox(width: AppSpacing.s8),
                            Expanded(
                              child: Text(
                                RecoveryVerdict.label(verdict, l10n),
                                style: context.appTheme.type.heading.copyWith(
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          l10n.healthRecoveryConfidence(
                            _confidenceLabel(confidence, l10n),
                            (coverage * 100).round(),
                          ),
                          style: context.microCaptionStyle,
                        ),
                      ],
                    );
                    final indicator = _RecoveryScore(
                      score: scoreValue.toDouble(),
                      color: scoreColor,
                      diameter: math.min(
                        (AppSpacing.s64 + AppSpacing.s24) * scale,
                        constraints.maxWidth,
                      ),
                    );
                    if (constraints.maxWidth < 260 * scale) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          summary,
                          const SizedBox(height: AppSpacing.s16),
                          indicator,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: summary),
                        const SizedBox(width: AppSpacing.s16),
                        indicator,
                      ],
                    );
                  },
                ),
                if (freshnessHours != null && freshnessHours > 36) ...[
                  const SizedBox(height: AppSpacing.s12),
                  AppBadge(
                    label: l10n.healthRecoveryWorstFreshness(
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
                const SizedBox(height: AppSpacing.s12),
                const AppGroupedDivider(indent: 0),
                AppTappable(
                  key: const Key('health-recovery-evidence'),
                  semanticsLabel: _showEvidence
                      ? l10n.healthRecoveryWhyLess
                      : l10n.healthRecoveryWhyTitle,
                  onPress: () => setState(() => _showEvidence = !_showEvidence),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppControlHeights.touchTarget,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _showEvidence
                                ? l10n.healthRecoveryWhyLess
                                : l10n.healthRecoveryWhyTitle,
                            style: context.captionMediumStyle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Icon(
                          _showEvidence
                              ? FLucideIcons.chevronUp
                              : FLucideIcons.chevronDown,
                          size: AppIconSizes.sm,
                          color: colors.mutedForeground,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSizeFade(
                  visible: _showEvidence,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.s12),
                      Text(
                        RecoveryVerdict.suggestion(verdict, l10n),
                        style: context.bodyCaptionStyle,
                      ),
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

class _RecoveryScore extends StatelessWidget {
  const _RecoveryScore({
    required this.score,
    required this.color,
    required this.diameter,
  });

  final double score;
  final Color color;
  final double diameter;

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.of(context).healthRecoveryTitle,
    value: '${score.round()} / 100',
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: diameter,
        child: CustomPaint(
          painter: _RecoveryScorePainter(
            score: score,
            color: color,
            track: color.withValues(alpha: AppOpacity.light),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedValueText(
                  value: score,
                  format: (value) => '${value.round()}',
                  style: context.appTheme.type.displaySmall.copyWith(
                    color: color,
                  ),
                ),
                Text('/ 100', style: context.microCaptionStyle),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _RecoveryScorePainter extends CustomPainter {
  const _RecoveryScorePainter({
    required this.score,
    required this.color,
    required this.track,
  });

  final double score;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(AppStroke.indicator);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppStroke.indicator
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * (score / 100).clamp(0, 1),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RecoveryScorePainter oldDelegate) =>
      score != oldDelegate.score ||
      color != oldDelegate.color ||
      track != oldDelegate.track;
}

class _RecoveryInsufficientState extends StatelessWidget {
  const _RecoveryInsufficientState({
    required this.verdict,
    required this.color,
    this.components = const [],
    required this.expanded,
    required this.onToggle,
  });

  final String verdict;
  final Color color;
  final List<Map<String, Object?>> components;
  final bool expanded;
  final VoidCallback onToggle;

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
              size: AppSpacing.s40,
              iconSize: AppIconSizes.md,
              backgroundOpacity: AppOpacity.medium,
              foregroundOpacity: 1,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.healthRecoveryTitle, style: context.captionStyle),
                  Text(
                    RecoveryVerdict.label(verdict, l10n),
                    style: context.labelStyle.copyWith(color: color),
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: expanded
                  ? FLucideIcons.chevronUp
                  : FLucideIcons.chevronDown,
              tooltip: expanded
                  ? l10n.healthRecoveryWhyLess
                  : l10n.healthRecoveryWhyTitle,
              onPress: onToggle,
            ),
          ],
        ),
        if (expanded) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            RecoveryVerdict.suggestion(verdict, l10n),
            style: context.bodyCaptionStyle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          for (final component in components) ...[
            const SizedBox(height: AppSpacing.s8),
            _RecoveryEvidenceRow(component: component),
          ],
        ],
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
    final state = component['status'];
    final recentLabel = recent == null ? '' : _recoveryValue(metric, recent);
    final message = state == 'missing_recent'
        ? l10n.healthRecoveryMissingRecent(_recoveryMetricLabel(l10n, metric))
        : state == 'learning'
        ? l10n.healthRecoveryLearning(
            _recoveryMetricLabel(l10n, metric),
            baselineSamples ?? 0,
            (component['baseline_days_required'] as num?)?.toInt() ?? 5,
          )
        : delta == null
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
    final evidenceMeta = component['reference_basis'] == 'user_goal'
        ? l10n.healthRecoveryGoalReference(
            (component['reference_value'] as num).toStringAsFixed(1),
            recentSamples ?? 0,
          )
        : baseline != null
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
              if (component['source_id'] case final String sourceId) ...[
                const SizedBox(height: AppSpacing.s2),
                Text(
                  [
                    healthMetricSourceFromId(sourceId)?.label ??
                        l10n.healthUnknownSource,
                    if (component['source_device'] case final String device
                        when device.isNotEmpty)
                      device,
                    if (metric == 'hrv')
                      if (component['measurement_method']
                          case final String method
                          when method == 'sdnn' || method == 'rmssd')
                        method.toUpperCase(),
                    if (component['freshness_hours'] case final num hours)
                      _ago(
                        l10n,
                        DateTime.now().toUtc().subtract(
                          Duration(minutes: (hours * 60).round()),
                        ),
                      ),
                  ].join(' · '),
                  style: context.microCaptionStyle,
                ),
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
          size: AppSpacing.s28,
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
