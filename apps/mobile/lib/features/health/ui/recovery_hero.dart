part of 'health_today_page.dart';

class _RecoveryHero extends ConsumerStatefulWidget {
  const _RecoveryHero();

  @override
  ConsumerState<_RecoveryHero> createState() => _RecoveryHeroState();
}

class _RecoveryHeroState extends ConsumerState<_RecoveryHero> {
  static const int _visibleActionCount = 2;
  bool _showAllActions = false;

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
            child: Center(child: FCircularProgress()),
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
            final scoreText = score == null ? '—' : '$score';
            final color = RecoveryVerdict.color(verdict, colors);
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
                    if (score != null)
                      Text(
                        scoreText,
                        // Hero rule (§8.1): the recovery score is the
                        // stage's display-scale number.
                        style: TypographyTokens.numericDisplay.copyWith(
                          color: color,
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

/// Only surfaces when there is a real alert or in-flight run — no empty loaders.
class _RecoveryAlertPanel extends ConsumerWidget {
  const _RecoveryAlertPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artifactAsync = ref.watch(
      health_agent_providers.latestRecoveryAlertArtifactProvider,
    );
    final runAsync = ref.watch(
      health_agent_providers.latestRecoveryAlertRunProvider,
    );
    final l10n = AppLocalizations.of(context);

    // Quiet while still resolving — do not paint loading shells on Today.
    if (artifactAsync.isLoading && !artifactAsync.hasValue) {
      return const SizedBox.shrink();
    }
    if (artifactAsync.hasError && !artifactAsync.hasValue) {
      return AgentResultPanelStateCard(
        icon: FLucideIcons.triangleAlert,
        title: l10n.commonError,
        message: userSafeErrorMessage(context, artifactAsync.error!),
        error: true,
        onRetry: () => ref.invalidate(
          health_agent_providers.latestRecoveryAlertArtifactProvider,
        ),
      );
    }

    final artifact = artifactAsync.value;
    final run = runAsync.value;
    // Ready runs with no artifact are silent (no status-only noise).
    if (artifact == null &&
        (run == null ||
            (run.status != AgentRunLifecycleStatus.running &&
                run.status != AgentRunLifecycleStatus.failed))) {
      return const SizedBox.shrink();
    }
    final metaLabel = l10n.healthBriefingUpdated(
      _ago(l10n, artifact?.createdAt ?? run!.startedAt),
    );
    return AgentResultSurface(
      artifact: artifact,
      run: run,
      metaLabel: metaLabel,
      layout: AgentResultCardLayout.summary,
      summaryMaxLines: 5,
      onOpen: artifact == null
          ? null
          : () => context.push(AgentArtifactRoutes.detail(artifact.id)),
      onRetry: () => _retryRecoveryAlert(ref),
    );
  }
}

Future<void> _retryRecoveryAlert(WidgetRef ref) async {
  final controller = await ref.read(agentRunControllerProvider.future);
  await controller.runOnceById(kRecoveryAlertAgentId);
  ref.invalidate(health_agent_providers.latestRecoveryAlertArtifactProvider);
  ref.invalidate(health_agent_providers.latestRecoveryAlertRunProvider);
  ref.invalidate(health_agent_providers.latestHealthReviewAgentResultsProvider);
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
