/// HealthOS Today surface (`docs/healthos-domain.md` §8, D-2.5b
/// follow-up).
///
/// Renders HealthKit/Garmin sync status, recovery, key metrics, weekly
/// summary, and the latest Morning Briefing. Trend and Plan now have MVP
/// surfaces; Today stays the dense operational entry point.
///
/// Chrome matches the rest of LifeOS (`docs/lifeos-shell.md` §3): the
/// ForUI `FScaffold` + `FHeader.nested` shell, `SoftCard` surfaces and
/// `context.theme` tokens — never Material `Scaffold` / `Theme.of` —
/// so HealthOS reads as the same app as Finance / Knowledge.
library;

import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell_chrome.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as health_agent_providers;
import '../data/health_metric_source.dart';
import '../data/health_sync_service.dart';
import '../data/providers.dart' as health_data;
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'body_measurement_entry_sheet.dart';
import 'garmin_sync_status_card.dart';
import 'health_metric_colors.dart';
import 'health_today_providers.dart';
import 'health_trend_page.dart' show healthTrendPath;
import 'recovery_verdict.dart';

class HealthTodayPage extends ConsumerWidget {
  const HealthTodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.healthTodayTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.scale),
          semanticsLabel: l10n.healthRecordBodyMetricAction,
          onPress: () async {
            final saved = await showBodyMeasurementEntrySheet(
              context: context,
              initialKind: HealthMetricKind.weight,
            );
            if (saved == true) ref.invalidate(healthTodaySnapshotProvider);
          },
        ),
      ],
      child: ListView(
        padding: shellTabContentPadding(context),
        children: const [
          FadeSlideIn(child: _DataSourcePanel()),
          SizedBox(height: AppSpacing.s16),
          FadeSlideIn(child: _RecoveryHero()),
          SizedBox(height: AppSpacing.s16),
          FadeSlideIn(child: _MetricGrid()),
          SizedBox(height: AppSpacing.s16),
          FadeSlideIn(child: _WeeklySummaryPanel()),
          SizedBox(height: AppSpacing.s16),
          FadeSlideIn(child: _BriefingPanel()),
        ],
      ),
    );
  }
}

class _DataSourcePanel extends StatelessWidget {
  const _DataSourcePanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HealthKitSyncCard(),
              SizedBox(height: AppSpacing.s8),
              GarminSyncStatusCard(),
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _HealthKitSyncCard()),
            SizedBox(width: AppSpacing.s8),
            Expanded(child: GarminSyncStatusCard()),
          ],
        );
      },
    );
  }
}

class _HealthKitSyncCard extends ConsumerStatefulWidget {
  const _HealthKitSyncCard();

  @override
  ConsumerState<_HealthKitSyncCard> createState() => _HealthKitSyncCardState();
}

class _HealthKitSyncCardState extends ConsumerState<_HealthKitSyncCard> {
  bool _syncing = false;
  HealthSyncResult? _lastResult;

  Future<void> _syncHealthKit() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final service = await ref.read(
        health_data.healthSyncServiceProvider.future,
      );
      if (!await service.hasPermissions()) {
        final granted = await service.requestPermissions();
        if (!granted) {
          setState(() {
            _lastResult = HealthSyncResult.skipped(
              startedAt: DateTime.now().toUtc(),
              errorMessage: AppLocalizations.of(
                context,
              ).healthSyncPermissionDenied,
            );
          });
          return;
        }
      }
      final result = await service.syncRange();
      setState(() => _lastResult = result);
      ref.invalidate(healthTodaySnapshotProvider);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final optIns = ref.watch(core_auth.domainOptInsProvider).value;
    final enabled = optIns?.contains(DomainScope.health) ?? false;

    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        children: [
          AppIconTile(
            icon: enabled ? FLucideIcons.activity : FLucideIcons.circleOff,
            color: _healthKitColor(enabled),
            size: 32,
            iconSize: AppIconSizes.h18,
            backgroundOpacity: AppOpacity.whisper,
            foregroundOpacity: AppOpacity.strong,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.healthKitTitle,
                  style: context.labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  _healthKitText(l10n, enabled),
                  style: context.captionStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          if (_syncing)
            const SizedBox(
              width: AppIconSizes.sm,
              height: AppIconSizes.sm,
              child: FCircularProgress(),
            )
          else
            FButton(
              variant: FButtonVariant.outline,
              onPress: enabled ? _syncHealthKit : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
                  const SizedBox(width: AppSpacing.s6),
                  Text(l10n.healthSyncAction),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _healthKitColor(bool enabled) {
    final colors = context.theme.colors;
    if (!enabled) return colors.mutedForeground;
    final result = _lastResult;
    if (_syncing) return colors.primary;
    if (result == null) return colors.mutedForeground;
    return result.ok ? colors.primary : colors.destructive;
  }

  String _healthKitText(AppLocalizations l10n, bool enabled) {
    if (!enabled) return l10n.healthNotEnabled;
    if (_syncing) return l10n.healthSyncingData;
    final result = _lastResult;
    if (result == null) return l10n.healthSyncReady;
    if (result.ok) {
      return l10n.healthSyncResult('${result.unchanged}', '${result.upserted}');
    }
    return result.errorMessage ?? l10n.healthSyncFailed;
  }
}

class _RecoveryHero extends ConsumerWidget {
  const _RecoveryHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recoverySignalProvider);
    final typography = context.theme.typography;
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
          style: typography.xs.copyWith(color: colors.destructive),
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
                      style: typography.xl.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (score != null) ...[
                    const SizedBox(width: AppSpacing.s8),
                    Text(
                      scoreText,
                      style: typography.sm.copyWith(
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
        return SizedBox(
          height: AppChartHeights.sparklineLg,
          child: CustomPaint(
            size: Size.infinite,
            painter: _SparklinePainter(
              values: values,
              color: colors.primary.withValues(alpha: AppOpacity.prominent),
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

class _MetricGrid extends ConsumerStatefulWidget {
  const _MetricGrid();

  @override
  ConsumerState<_MetricGrid> createState() => _MetricGridState();
}

class _MetricGridState extends ConsumerState<_MetricGrid> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final metrics = ref.watch(healthTodayMetricGridProvider);

    AsyncValue<HealthMetric?> metric(
      HealthMetric? Function(HealthTodayMetricGridModel model) select,
    ) {
      if (metrics.hasValue) {
        return AsyncValue.data(select(metrics.requireValue));
      }
      if (metrics.hasError) {
        return AsyncValue.error(
          metrics.error!,
          metrics.stackTrace ?? StackTrace.current,
        );
      }
      return const AsyncValue.loading();
    }

    MetricTrend? trend(
      MetricTrend? Function(HealthTodayMetricGridModel model) select,
    ) {
      final model = metrics.value;
      return model == null ? null : select(model);
    }

    final cards = <Widget>[
      _SleepCard(
        async: metric((m) => m.sleep),
        trend: trend((m) => m.sleepTrend),
      ),
      _BodyBatteryCard(
        async: metric((m) => m.bodyBattery),
        trend: trend((m) => m.bodyBatteryTrend),
      ),
      _StressCard(
        async: metric((m) => m.stress),
        trend: trend((m) => m.stressTrend),
      ),
      _HrvCard(async: metric((m) => m.hrv), trend: trend((m) => m.hrvTrend)),
      _HeartRateCard(
        async: metric((m) => m.heartRate),
        trend: trend((m) => m.heartRateTrend),
      ),
      _RhrCard(async: metric((m) => m.rhr), trend: trend((m) => m.rhrTrend)),
      _StepsCard(
        async: metric((m) => m.steps),
        trend: trend((m) => m.stepsTrend),
      ),
      _WorkoutCard(async: metric((m) => m.workout)),
      _ActiveEnergyCard(
        async: metric((m) => m.energy),
        trend: trend((m) => m.energyTrend),
      ),
      _TrainingLoadCard(async: metric((m) => m.trainingLoad)),
      _Spo2Card(async: metric((m) => m.spo2)),
    ];
    final visibleCards = _expanded ? cards : cards.take(4).toList();
    final l10n = AppLocalizations.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= Breakpoints.contentThreeColumn
            ? 3
            : maxWidth < 360
            ? 1
            : 2;
        const gap = AppSpacing.s8;
        final computedCardWidth = maxWidth.isFinite
            ? (maxWidth - gap * (columns - 1)) / columns
            : 220.0;
        final cardWidth = computedCardWidth < 0 ? 0.0 : computedCardWidth;
        return Column(
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in visibleCards)
                  SizedBox(width: cardWidth, child: card),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            SizedBox(
              width: double.infinity,
              child: AppQuietButton(
                label: _expanded
                    ? l10n.healthShowKeyMetrics
                    : l10n.healthShowAllMetrics,
                onPress: () => setState(() => _expanded = !_expanded),
                expanded: true,
                prefix: Icon(
                  _expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                  size: AppIconSizes.sm,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.moon,
      label: l10n.healthSleepMetricLabel,
      trendKind: HealthMetricKind.sleepSession,
      accent: HealthMetricColors.sleep,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          final hours = _secondsToHours(m.value, m.unit);
          final stages = _parseSleepStages(m.payloadJson);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ValueBig(
                value: '${_round(hours)}',
                unit: 'h',
                sub: _ago(l10n, m.capturedAt),
                trend: trend,
                metric: m,
              ),
              if (stages != null) ...[
                const SizedBox(height: AppSpacing.s4),
                _SleepStageBar(
                  deepSeconds: stages.deep,
                  remSeconds: stages.rem,
                  lightSeconds: stages.light,
                  awakeSeconds: stages.awake,
                  totalSeconds: m.value,
                  l10n: l10n,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Parsed sleep stage durations from payloadJson.
class _SleepStages {
  const _SleepStages({
    required this.deep,
    required this.rem,
    required this.light,
    this.awake = 0,
  });
  final double deep;
  final double rem;
  final double light;
  final double awake;
}

_SleepStages? _parseSleepStages(String? payloadJson) {
  if (payloadJson == null || payloadJson.isEmpty) return null;
  try {
    final json = jsonDecode(payloadJson) as Map<String, dynamic>;
    // Support both short keys (Garmin + HealthKit) and legacy long keys.
    final deep =
        ((json['deep'] ?? json['deepSleepSeconds']) as num?)?.toDouble() ?? 0;
    final rem =
        ((json['rem'] ?? json['remSleepSeconds']) as num?)?.toDouble() ?? 0;
    final light =
        ((json['light'] ?? json['lightSleepSeconds']) as num?)?.toDouble() ?? 0;
    final awake =
        ((json['awake'] ?? json['awakeSleepSeconds']) as num?)?.toDouble() ?? 0;
    if (deep == 0 && rem == 0 && light == 0) return null;
    return _SleepStages(deep: deep, rem: rem, light: light, awake: awake);
  } catch (_) {
    return null;
  }
}

/// Compact horizontal bar showing deep/REM/light/awake proportions.
class _SleepStageBar extends StatelessWidget {
  const _SleepStageBar({
    required this.deepSeconds,
    required this.remSeconds,
    required this.lightSeconds,
    required this.awakeSeconds,
    required this.totalSeconds,
    required this.l10n,
  });

  final double deepSeconds;
  final double remSeconds;
  final double lightSeconds;
  final double awakeSeconds;
  final double totalSeconds;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    if (totalSeconds <= 0) return const SizedBox.shrink();

    final deepPct = deepSeconds / totalSeconds;
    final remPct = remSeconds / totalSeconds;
    final awakePct = awakeSeconds / totalSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: SizedBox(
            height: AppSpacing.s4,
            child: Row(
              children: [
                if (deepPct > 0)
                  Expanded(
                    flex: (deepPct * 100).round().clamp(1, 100),
                    child: Container(color: colors.primary),
                  ),
                if (remPct > 0)
                  Expanded(
                    flex: (remPct * 100).round().clamp(1, 100),
                    child: Container(
                      color: colors.primary.withValues(
                        alpha: AppOpacity.prominent,
                      ),
                    ),
                  ),
                if (awakePct > 0)
                  Expanded(
                    flex: (awakePct * 100).round().clamp(1, 100),
                    child: Container(
                      color: colors.destructive.withValues(
                        alpha: AppOpacity.muted,
                      ),
                    ),
                  ),
                Expanded(
                  flex: ((1 - deepPct - remPct - awakePct) * 100).round().clamp(
                    1,
                    100,
                  ),
                  child: Container(color: colors.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Wrap(
          spacing: AppSpacing.s6,
          runSpacing: AppSpacing.s2,
          children: [
            _stageChip(
              typography,
              colors.primary,
              l10n.healthSleepDeepLabel,
              deepSeconds,
            ),
            _stageChip(
              typography,
              colors.primary.withValues(alpha: AppOpacity.prominent),
              l10n.healthSleepRemLabel,
              remSeconds,
            ),
            _stageChip(
              typography,
              colors.mutedForeground,
              l10n.healthSleepLightLabel,
              lightSeconds,
            ),
            if (awakeSeconds > 0)
              _stageChip(
                typography,
                colors.destructive.withValues(alpha: AppOpacity.prominent),
                l10n.healthSleepAwakeLabel,
                awakeSeconds,
              ),
          ],
        ),
      ],
    );
  }

  Widget _stageChip(
    FTypography typography,
    Color color,
    String label,
    double seconds,
  ) {
    final hours = seconds / 3600.0;
    return Text(
      '$label ${_round(hours)}h',
      style: typography.xs.copyWith(color: color, fontSize: 10),
    );
  }
}

class _HrvCard extends StatelessWidget {
  const _HrvCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.heartPulse,
      label: l10n.healthHrvMetricLabel,
      trendKind: HealthMetricKind.hrvDaily,
      accent: HealthMetricColors.hrv,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)}',
            unit: m.unit,
            sub: _ago(l10n, m.capturedAt),
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.heartPulse,
      label: l10n.healthHeartRateMetricLabel,
      trendKind: HealthMetricKind.heartRateDaily,
      accent: HealthMetricColors.heartRate,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)}',
            unit: m.unit,
            sub: _ago(l10n, m.capturedAt),
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.dumbbell,
      label: l10n.healthWorkoutMetricLabel,
      trendKind: HealthMetricKind.workoutSession,
      accent: HealthMetricColors.workout,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          final minutes = (m.value / 60).round();
          final payload = _parseJsonMap(m.payloadJson);
          final distMeters = (payload['totalDistanceMeters'] as num?)
              ?.toDouble();
          final cal = (payload['totalEnergyKcal'] as num?)?.toDouble();
          final parts = <String>[];
          if (distMeters != null && distMeters > 0) {
            parts.add('${_round(distMeters / 1000)}km');
          }
          if (cal != null && cal > 0) {
            parts.add('${cal.round()}kcal');
          }
          final detail = parts.isEmpty ? '' : '${parts.join(' · ')} · ';
          return _ValueBig(
            value: '$minutes',
            unit: 'm',
            sub: '$detail${_ago(l10n, m.capturedAt)}',
            metric: m,
          );
        },
      ),
    );
  }
}

class _StepsCard extends ConsumerWidget {
  const _StepsCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final walking = ref.watch(latestWalkingDistanceProvider);
    return _MetricCard(
      icon: FLucideIcons.footprints,
      trendKind: HealthMetricKind.stepsDaily,
      label: l10n.healthStepsMetricLabel,
      accent: HealthMetricColors.steps,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          // Pair the distance line with steps when both refer to the
          // same UTC day; otherwise fall back to the time-ago line so
          // we don't show a stale-day distance next to today's steps.
          final stepsDay = _utcDayKey(m.capturedAt);
          final wm = walking.asData?.value;
          final sub = wm != null && _utcDayKey(wm.capturedAt) == stepsDay
              ? '${(wm.value / 1000.0).toStringAsFixed(1)} km · ${_ago(l10n, m.capturedAt)}'
              : _ago(l10n, m.capturedAt);
          return _ValueBig(
            value: _formatSteps(m.value),
            sub: sub,
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _ActiveEnergyCard extends StatelessWidget {
  const _ActiveEnergyCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.flame,
      label: l10n.healthEnergyMetricLabel,
      trendKind: HealthMetricKind.activeEnergyDaily,
      accent: HealthMetricColors.totalEnergy,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${m.value.round()}',
            unit: 'kcal',
            sub: _ago(l10n, m.capturedAt),
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _BodyBatteryCard extends StatelessWidget {
  const _BodyBatteryCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.battery,
      label: l10n.healthBodyBatteryMetricLabel,
      trendKind: HealthMetricKind.bodyBatteryDaily,
      accent: HealthMetricColors.bodyBattery,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          final payload = _parseJsonMap(m.payloadJson);
          final charged = (payload['charged'] as num?)?.toInt() ?? 0;
          final drained = (payload['drained'] as num?)?.toInt() ?? 0;
          final net = charged - drained;
          final netStr = net >= 0 ? '+$net' : '$net';
          return _ValueBig(
            value: '${m.value.round()}',
            sub: '$netStr · ${_ago(l10n, m.capturedAt)}',
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _StressCard extends StatelessWidget {
  const _StressCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.brain,
      trendKind: HealthMetricKind.stressDaily,
      label: l10n.healthStressMetricLabel,
      accent: HealthMetricColors.stress,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${m.value.round()}',
            sub: _ago(l10n, m.capturedAt),
            metric: m,
          );
        },
      ),
    );
  }
}

class _RhrCard extends StatelessWidget {
  const _RhrCard({required this.async, this.trend});
  final AsyncValue<HealthMetric?> async;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.heart,
      trendKind: HealthMetricKind.rhrDaily,
      label: l10n.healthRhrMetricLabel,
      accent: HealthMetricColors.rhr,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${m.value.round()}',
            sub: _ago(l10n, m.capturedAt),
            trend: trend,
            metric: m,
          );
        },
      ),
    );
  }
}

class _TrainingLoadCard extends StatelessWidget {
  const _TrainingLoadCard({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.flame,
      label: l10n.healthTrainingLoadMetricLabel,
      trendKind: HealthMetricKind.trainingLoadDaily,
      accent: HealthMetricColors.trainingLoad,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)}',
            sub: _ago(l10n, m.capturedAt),
            metric: m,
          );
        },
      ),
    );
  }
}

class _Spo2Card extends StatelessWidget {
  const _Spo2Card({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.wind,
      trendKind: HealthMetricKind.spo2Daily,
      label: l10n.healthSpo2MetricLabel,
      accent: HealthMetricColors.spo2,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)}',
            unit: '%',
            sub: _ago(l10n, m.capturedAt),
            metric: m,
          );
        },
      ),
    );
  }
}

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
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      onPress: trendKind == null
          ? null
          : () => context.go(healthTrendPath(metricKind: trendKind)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetricCardHeader(
              icon: icon,
              title: label,
              color: accent,
              showChevron: trendKind != null,
            ),
            const SizedBox(height: AppSpacing.s12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricCardHeader extends StatelessWidget {
  const _MetricCardHeader({
    required this.icon,
    required this.title,
    required this.color,
    required this.showChevron,
  });

  final IconData icon;
  final String title;
  final Color color;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      children: [
        AppIconTile(icon: icon, color: color),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            title,
            style: context.mutedLabelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showChevron)
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.h18,
            color: colors.mutedForeground.withValues(
              alpha: AppOpacity.disabled,
            ),
          ),
      ],
    );
  }
}

class _ValueBig extends StatelessWidget {
  const _ValueBig({
    required this.value,
    required this.sub,
    this.unit,
    this.trend,
    this.metric,
  });
  final String value;
  final String sub;
  final String? unit;
  final MetricTrend? trend;
  final HealthMetric? metric;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
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
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typography.lg.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (unit != null && unit!.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.s2),
              Text(
                unit!,
                style: context.captionStyle.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
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

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});
  final MetricTrend trend;

  @override
  Widget build(BuildContext context) {
    final dir = trend.direction;
    if (dir == TrendDirection.flat) return const SizedBox.shrink();
    final colors = context.theme.colors;
    final isUp = dir == TrendDirection.up;
    final color = isUp ? colors.primary : colors.destructive;
    final arrow = isUp ? '↑' : '↓';
    final pct = trend.deltaPct.abs().round();
    return Text(
      '$arrow$pct%',
      style: context.captionLabelStyle.copyWith(color: color),
    );
  }
}

class _ValueDash extends StatelessWidget {
  const _ValueDash();

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('—', style: typography.lg.copyWith(color: colors.mutedForeground)),
        const SizedBox(height: AppSpacing.s2),
        Text(
          AppLocalizations.of(context).healthNoData,
          style: context.captionStyle,
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

Map<String, dynamic> _parseJsonMap(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    return jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    return const {};
  }
}

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

class _HealthPanelHeader extends StatelessWidget {
  const _HealthPanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    return Row(
      children: [
        AppIconTile(
          icon: icon,
          color: color,
          size: 36,
          iconSize: AppIconSizes.h18,
          backgroundOpacity: AppOpacity.medium,
          foregroundOpacity: 1,
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: typography.sm.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                subtitle,
                style: context.captionStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.s8),
          trailing!,
        ],
      ],
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Row(
          children: [
            Icon(icon, size: AppIconSizes.h18, color: colors.mutedForeground),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                message,
                style: context.captionStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _BriefingPanel extends ConsumerStatefulWidget {
  const _BriefingPanel();

  @override
  ConsumerState<_BriefingPanel> createState() => _BriefingPanelState();
}

class _BriefingPanelState extends ConsumerState<_BriefingPanel> {
  bool _running = false;
  String? _errorMessage;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _errorMessage = null;
    });
    try {
      // ignore: unused_result
      ref.refresh(health_agent_providers.manualMorningBriefingRunProvider);
      await ref.read(
        health_agent_providers.manualMorningBriefingRunProvider.future,
      );
      ref.invalidate(health_agent_providers.latestMorningBriefingProvider);
    } on Object catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      health_agent_providers.latestMorningBriefingProvider,
    );
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        async.when(
          loading: () => const _BriefingSkeleton(),
          error: (e, _) => _BriefingError(message: '$e'),
          data: (record) =>
              _BriefingCard(record: record, running: _running, onRun: _run),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            _errorMessage!,
            style: typography.xs.copyWith(color: colors.destructive),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({
    required this.record,
    required this.running,
    required this.onRun,
  });

  final MemoryRecord? record;
  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = record;
    if (r == null) return _BriefingEmpty(running: running, onRun: onRun);
    final outcome = r.payload['outcome'];
    final source = outcome is Map<String, Object?>
        ? outcome['synthesis_source']
        : null;
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final sourceLabel = source == 'llm' ? 'LLM' : l10n.healthBriefingAuto;
    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HealthPanelHeader(
            icon: FLucideIcons.sun,
            title: l10n.healthBriefingTitle,
            subtitle: l10n.healthBriefingUpdated(_ago(l10n, r.updatedAt)),
            color: colors.primary,
            trailing: source is String && source.isNotEmpty
                ? AppBadge(
                    label: sourceLabel,
                    size: AppBadgeSize.compact,
                    tone: source == 'llm'
                        ? AppBadgeTone.accent
                        : AppBadgeTone.neutral,
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.s12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.muted.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Text(
                r.summary,
                style: typography.sm.copyWith(height: 1.45),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: AppQuietButton(
              label: running
                  ? l10n.healthBriefingGenerating
                  : l10n.healthBriefingUpdate,
              onPress: running ? null : onRun,
              prefix: const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
              busy: running,
            ),
          ),
        ],
      ),
    );
  }
}

class _BriefingEmpty extends StatelessWidget {
  const _BriefingEmpty({required this.running, required this.onRun});

  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HealthPanelHeader(
            icon: FLucideIcons.sunset,
            title: l10n.healthBriefingTitle,
            subtitle: l10n.healthBriefingEmpty,
            color: colors.mutedForeground,
          ),
          const SizedBox(height: AppSpacing.s12),
          _InlineEmptyState(
            icon: FLucideIcons.sparkles,
            message: l10n.healthBriefingEmptyHint,
          ),
          const SizedBox(height: AppSpacing.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: AppQuietButton(
              label: running
                  ? l10n.healthBriefingGenerating
                  : l10n.healthBriefingGenerate,
              onPress: running ? null : onRun,
              prefix: const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
              busy: running,
            ),
          ),
        ],
      ),
    );
  }
}

class _BriefingSkeleton extends StatelessWidget {
  const _BriefingSkeleton();

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
              SkeletonBox(width: 120, height: 14, radius: AppRadius.xs),
            ],
          ),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(width: 200, height: 14),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(width: 80, height: 10),
        ],
      ),
    );
  }
}

class _BriefingError extends StatelessWidget {
  const _BriefingError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppStatusBanner(
      kind: AppStatusKind.error,
      message: AppLocalizations.of(context).healthBriefingLoadFailed(message),
      icon: FLucideIcons.circleAlert,
    );
  }
}
