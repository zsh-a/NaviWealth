part of 'health_today_page.dart';

class _RecoveryHero extends ConsumerStatefulWidget {
  const _RecoveryHero();

  @override
  ConsumerState<_RecoveryHero> createState() => _RecoveryHeroState();
}

class _RecoveryHeroState extends ConsumerState<_RecoveryHero> {
  static const int _visibleActionCount = 2;
  bool _showAllActions = false;
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
            final primaryActions = actions
                .take(_visibleActionCount)
                .toList(growable: false);
            final overflowActions = actions.length > _visibleActionCount
                ? actions.skip(_visibleActionCount).toList(growable: false)
                : const <HealthPlanAction>[];
            final hasMore = overflowActions.isNotEmpty;
            final enabled =
                ref
                    .watch(core_auth.domainOptInsProvider)
                    .value
                    ?.contains(DomainScope.health) ??
                false;
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
                AppBadge(
                  label: l10n.healthRecoveryConfidence(
                    _confidenceLabel(confidence, l10n),
                    (coverage * 100).round(),
                  ),
                  size: AppBadgeSize.compact,
                ),
                if (freshnessHours != null) ...[
                  const SizedBox(height: AppSpacing.s6),
                  AppBadge(
                    label: l10n.healthRecoveryFreshness(
                      _ago(
                        l10n,
                        DateTime.now().toUtc().subtract(
                          Duration(minutes: (freshnessHours * 60).round()),
                        ),
                      ),
                    ),
                    tone: freshnessHours > 36
                        ? AppBadgeTone.warning
                        : AppBadgeTone.neutral,
                    size: AppBadgeSize.compact,
                  ),
                ],
                if (components.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s12),
                  AppRevealControl(
                    expanded: _showEvidence,
                    collapsedLabel: l10n.healthRecoveryWhyTitle,
                    expandedLabel: l10n.healthRecoveryWhyLess,
                    onToggle: () =>
                        setState(() => _showEvidence = !_showEvidence),
                  ),
                  AnimatedSizeFade(
                    visible: _showEvidence,
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s8),
                      child: Column(
                        children: [
                          for (var i = 0; i < components.length; i++) ...[
                            if (i > 0) const SizedBox(height: AppSpacing.s6),
                            _RecoveryEvidenceRow(component: components[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                if (!enabled) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    l10n.healthPlanEnableHint,
                    style: context.captionStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s16),
                  Text(
                    l10n.healthPlanTodayActions,
                    style: context.microCaptionStyle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  for (var i = 0; i < primaryActions.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.s8),
                    _PlanActionRow(
                      action: primaryActions[i],
                      color: colors.primary,
                    ),
                  ],
                  if (hasMore) ...[
                    AnimatedSizeFade(
                      visible: _showAllActions,
                      alignment: Alignment.topCenter,
                      child: Column(
                        children: [
                          for (final action in overflowActions) ...[
                            const SizedBox(height: AppSpacing.s8),
                            _PlanActionRow(
                              action: action,
                              color: colors.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    AppRevealControl(
                      expanded: _showAllActions,
                      collapsedLabel: l10n.commonRevealMore(
                        overflowActions.length,
                      ),
                      expandedLabel: l10n.commonRevealLess,
                      onToggle: () =>
                          setState(() => _showAllActions = !_showAllActions),
                    ),
                  ],
                ],
                const SizedBox(height: AppSpacing.s16),
                const _RecoverySparkline(),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  l10n.healthPlanDisclaimer,
                  style: context.microCaptionStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
        Expanded(child: Text(message, style: context.captionStyle)),
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

/// 7-day HRV sparkline shown beneath the recovery card.
class _RecoverySparkline extends ConsumerWidget {
  const _RecoverySparkline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recoverySparklineProvider);
    final colors = context.theme.colors;
    return async.when(
      // loading: intentionally empty — the sparkline only renders with >= 2
      // points, so a placeholder would promise a chart that may never appear.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (values) {
        if (values.length < 2) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        return Semantics(
          image: true,
          label:
              '${l10n.healthRecentHrvLabel}: ${values.map((v) => _round(v)).join(', ')}',
          child: SizedBox(
            height: AppChartHeights.sparkline,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SparklinePainter(
                values: values,
                color: colors.primary.withValues(alpha: AppOpacity.prominent),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = max - min;
    const inset = 3.0;

    final paint = Paint()
      ..color = color
      ..strokeWidth = AppStroke.medium
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (range == 0) {
      final y = size.height / 2;
      canvas.drawLine(Offset(inset, y), Offset(size.width - inset, y), paint);
      canvas.drawCircle(
        Offset(size.width - inset, y),
        2.5,
        Paint()..color = color,
      );
      return;
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = inset + (i / (values.length - 1)) * (size.width - inset * 2);
      final y =
          inset + (1 - (values[i] - min) / range) * (size.height - inset * 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // Draw a dot at the last point.
    final lastX = size.width - inset;
    final lastY =
        inset + (1 - (values.last - min) / range) * (size.height - inset * 2);
    canvas.drawCircle(Offset(lastX, lastY), 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}
