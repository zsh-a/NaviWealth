part of 'health_today_page.dart';

class _RecoveryHero extends ConsumerWidget {
  const _RecoveryHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recoverySignalProvider);
    final colors = context.theme.colors;
    return SoftCard(
      level: SoftCardLevel.hero,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: async.when(
        loading: () => const SizedBox(
          height: AppControlHeights.compactLoadingState,
          child: Center(child: FCircularProgress()),
        ),
        error: (e, _) => Text(
          AppLocalizations.of(context).healthSyncFailed,
          style: context.captionStyle.copyWith(color: colors.destructive),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        data: (out) {
          final verdict = out?['verdict']?.toString() ?? 'insufficient_data';
          final score = out?['score'];
          final l10n = AppLocalizations.of(context);
          final scoreText = score == null ? '—' : '$score';
          final color = RecoveryVerdict.color(verdict, colors);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIconTile(
                    icon: RecoveryVerdict.icon(verdict),
                    color: color,
                    size: 40,
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
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    fit: FlexFit.loose,
                    child: Text(
                      RecoveryVerdict.label(verdict, l10n),
                      style: context.strongHeadlineStyle.copyWith(color: color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (score != null) ...[
                    const SizedBox(width: AppSpacing.s8),
                    Text(
                      scoreText,
                      style: context.theme.typography.body.sm.copyWith(
                        color: color.withValues(alpha: AppOpacity.strong),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                RecoveryVerdict.suggestion(verdict, l10n),
                style: context.bodyCaptionStyle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.s12),
              const _RecoverySparkline(),
            ],
          );
        },
      ),
    );
  }
}

class _RecoveryAlertPanel extends ConsumerWidget {
  const _RecoveryAlertPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artifact = ref
        .watch(health_agent_providers.latestRecoveryAlertArtifactProvider)
        .value;
    if (artifact == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final metaLabel = l10n.healthBriefingUpdated(
      _ago(l10n, artifact.createdAt),
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: AgentResultCard(
        artifact: artifact,
        metaLabel: metaLabel,
        onOpen: () => showAgentArtifactSheet(
          context: context,
          artifact: artifact,
          subtitle: metaLabel,
          onVisibilityChanged: () => ref.invalidate(
            health_agent_providers.latestRecoveryAlertArtifactProvider,
          ),
        ),
      ),
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
            height: AppChartHeights.sparklineLg,
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
