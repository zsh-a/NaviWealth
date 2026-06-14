/// HealthOS Today surface (`docs/healthos-domain.md` §8, D-2.5b
/// follow-up).
///
/// Renders the most recent Morning Briefing as the headline card with
/// a `Run now` affordance underneath. The Briefing is the only signal
/// HealthOS surfaces in-app today; Trend and Plan tabs keep the
/// placeholder until later milestones flesh them out.
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

import '../../../app/route_paths.dart';
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
import 'health_trend_page.dart' show TrendGroup, selectedTrendGroupProvider;
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
          FadeSlideIn(child: _HealthDataStatusNotice()),
          SizedBox(height: AppSpacing.s16),
          FadeSlideIn(child: GarminSyncStatusCard()),
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

class _HealthDataStatusNotice extends ConsumerStatefulWidget {
  const _HealthDataStatusNotice();

  @override
  ConsumerState<_HealthDataStatusNotice> createState() =>
      _HealthDataStatusNoticeState();
}

class _HealthDataStatusNoticeState
    extends ConsumerState<_HealthDataStatusNotice> {
  bool _running = false;
  HealthSyncResult? _lastResult;

  Future<void> _sync() async {
    if (_running) return;
    setState(() => _running = true);
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
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final optIns = ref.watch(core_auth.domainOptInsProvider).value;
    final enabled = optIns?.contains(DomainScope.health) ?? false;
    final result = _lastResult;

    final kind = !enabled
        ? AppStatusKind.warning
        : _running
        ? AppStatusKind.info
        : result == null
        ? AppStatusKind.info
        : result.ok
        ? AppStatusKind.success
        : AppStatusKind.error;
    final l10n = AppLocalizations.of(context);
    final text = !enabled
        ? l10n.healthNotEnabled
        : _running
        ? l10n.healthSyncingData
        : result == null
        ? l10n.healthSyncReady
        : result.ok
        ? l10n.healthSyncResult('${result.unchanged}', '${result.upserted}')
        : result.errorMessage ?? l10n.healthSyncFailed;
    final action = !enabled
        ? null
        : AppQuietButton(
            label: _running ? l10n.healthSyncingButton : l10n.healthSyncButton,
            onPress: _running ? null : _sync,
            prefix: _running
                ? const SizedBox(
                    width: AppIconSizes.xs,
                    height: AppIconSizes.xs,
                    child: FCircularProgress(),
                  )
                : const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
          );

    return AppStatusBanner(
      kind: kind,
      message: text,
      icon: enabled ? FLucideIcons.activity : FLucideIcons.circleOff,
      action: action,
      compact: true,
    );
  }
}

class _RecoveryHero extends ConsumerWidget {
  const _RecoveryHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recoverySignalProvider);
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return SoftCard(
      level: SoftCardLevel.hero,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: async.when(
        loading: () => const SizedBox(
          height: 96,
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: AppOpacity.medium),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      RecoveryVerdict.icon(verdict),
                      size: AppIconSizes.md,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Text(
                      l10n.healthRecoveryTitle,
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                        fontWeight: FontWeight.w600,
                      ),
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
                        color: color.withValues(alpha: 0.7),
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
          height: 32,
          child: CustomPaint(
            size: Size.infinite,
            painter: _SparklinePainter(
              values: values,
              color: colors.primary.withValues(alpha: 0.6),
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
      ..strokeWidth = 1.5
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
    final sleep = ref.watch(latestSleepSessionProvider);
    final hrv = ref.watch(latestHrvProvider);
    final heartRate = ref.watch(latestHeartRateProvider);
    final workout = ref.watch(latestWorkoutProvider);
    final steps = ref.watch(latestStepsProvider);
    final energy = ref.watch(latestActiveEnergyProvider);
    final bodyBattery = ref.watch(latestBodyBatteryProvider);
    final stress = ref.watch(latestStressProvider);
    final rhr = ref.watch(latestRhrProvider);
    final trainingLoad = ref.watch(latestTrainingLoadProvider);
    final spo2 = ref.watch(latestSpo2Provider);

    // Trends (7-day delta).
    final sleepTrend = ref.watch(
      metricTrendProvider(HealthMetricKind.sleepSession),
    );
    final bbTrend = ref.watch(
      metricTrendProvider(HealthMetricKind.bodyBatteryDaily),
    );
    final stressTrend = ref.watch(
      metricTrendProvider(HealthMetricKind.stressDaily),
    );
    final hrvTrend = ref.watch(metricTrendProvider(HealthMetricKind.hrvDaily));
    final hrTrend = ref.watch(
      metricTrendProvider(HealthMetricKind.heartRateDaily),
    );
    final rhrTrend = ref.watch(metricTrendProvider(HealthMetricKind.rhrDaily));
    final stepsTrend = ref.watch(
      metricTrendProvider(HealthMetricKind.stepsDaily),
    );
    final energyTrend = ref.watch(
      metricTrendProvider(HealthMetricKind.activeEnergyDaily),
    );

    final cards = <Widget>[
      _SleepCard(async: sleep, trend: sleepTrend.value),
      _BodyBatteryCard(async: bodyBattery, trend: bbTrend.value),
      _StressCard(async: stress, trend: stressTrend.value),
      _HrvCard(async: hrv, trend: hrvTrend.value),
      _HeartRateCard(async: heartRate, trend: hrTrend.value),
      _RhrCard(async: rhr, trend: rhrTrend.value),
      _StepsCard(async: steps, trend: stepsTrend.value),
      _WorkoutCard(async: workout),
      _ActiveEnergyCard(async: energy, trend: energyTrend.value),
      _TrainingLoadCard(async: trainingLoad),
      _Spo2Card(async: spo2),
    ];
    final visibleCards = _expanded ? cards : cards.take(6).toList();
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
      trendGroup: TrendGroup.recovery,
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
    final colors = context.theme.colors;
    final typography = context.theme.typography;
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
            height: 4,
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
                      color: colors.primary.withValues(alpha: 0.6),
                    ),
                  ),
                if (awakePct > 0)
                  Expanded(
                    flex: (awakePct * 100).round().clamp(1, 100),
                    child: Container(
                      color: colors.destructive.withValues(alpha: 0.3),
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
              colors.primary.withValues(alpha: 0.6),
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
                colors.destructive.withValues(alpha: 0.6),
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
      trendGroup: TrendGroup.recovery,
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
      trendGroup: TrendGroup.recovery,
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
      trendGroup: TrendGroup.activity,
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
      trendGroup: TrendGroup.activity,
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
      trendGroup: TrendGroup.activity,
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
      trendGroup: TrendGroup.recovery,
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
      trendGroup: TrendGroup.recovery,
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
      trendGroup: TrendGroup.recovery,
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
      trendGroup: TrendGroup.activity,
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
      trendGroup: TrendGroup.recovery,
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
    this.trendGroup,
  });
  final IconData icon;
  final String label;
  final Widget child;
  final Color accent;
  final TrendGroup? trendGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      onPress: trendGroup == null
          ? null
          : () {
              ref.read(selectedTrendGroupProvider.notifier).state = trendGroup!;
              context.go(AppRoutes.healthTrend);
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetricCardHeader(
              icon: icon,
              title: label,
              color: accent,
              showChevron: trendGroup != null,
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
            style: context.theme.typography.sm.copyWith(
              color: colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
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
    final colors = context.theme.colors;
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
                style: typography.xs.copyWith(
                  color: colors.mutedForeground,
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
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Flexible(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.muted.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: 1,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typography.xs.copyWith(
              color: colors.mutedForeground,
              fontSize: 10,
            ),
          ),
        ),
      ),
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
    final typography = context.theme.typography;
    final isUp = dir == TrendDirection.up;
    final color = isUp ? colors.primary : colors.destructive;
    final arrow = isUp ? '↑' : '↓';
    final pct = trend.deltaPct.abs().round();
    return Text(
      '$arrow$pct%',
      style: typography.xs.copyWith(color: color, fontWeight: FontWeight.w600),
    );
  }
}

class _ValueDash extends StatelessWidget {
  const _ValueDash();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
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

class _WeeklySummaryPanel extends ConsumerWidget {
  const _WeeklySummaryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(weeklySummaryProvider);
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (summary) {
        if (summary == null) return const SizedBox.shrink();
        return SoftCard(
          level: SoftCardLevel.raised,
          borderless: true,
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardCardHeader(
                icon: FLucideIcons.calendarDays,
                title: l10n.healthWeeklySummaryTitle,
                color: colors.mutedForeground,
              ),
              const SizedBox(height: AppSpacing.s12),
              Wrap(
                spacing: AppSpacing.s16,
                runSpacing: AppSpacing.s8,
                children: [
                  _summaryChip(
                    context,
                    Fmt.number(summary.totalSteps.round()),
                    l10n.healthStepsMetricLabel,
                  ),
                  if (summary.avgSleepHours > 0)
                    _summaryChip(
                      context,
                      '${_round(summary.avgSleepHours)}h',
                      l10n.healthSleepMetricLabel,
                    ),
                  if (summary.workoutCount > 0)
                    _summaryChip(
                      context,
                      '${summary.totalWorkoutMinutes}m · ${summary.workoutCount}×',
                      l10n.healthWorkoutMetricLabel,
                    ),
                  if (summary.avgHrv > 0)
                    _summaryChip(
                      context,
                      '${summary.avgHrv.round()}ms',
                      l10n.healthHrvMetricLabel,
                    ),
                  if (summary.avgRhr > 0)
                    _summaryChip(
                      context,
                      '${summary.avgRhr.round()}bpm',
                      l10n.healthRhrMetricLabel,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summaryChip(BuildContext context, String value, String label) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: typography.sm.copyWith(fontWeight: FontWeight.w600)),
        Text(
          label,
          style: typography.xs.copyWith(color: colors.mutedForeground),
        ),
      ],
    );
  }
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
    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: AppOpacity.medium),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(
                  FLucideIcons.sun,
                  size: AppIconSizes.md,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  l10n.healthBriefingTitle,
                  style: typography.sm.copyWith(
                    color: colors.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (source is String && source.isNotEmpty) ...[
                AppBadge(
                  label: source == 'llm' ? 'LLM' : l10n.healthBriefingAuto,
                  size: AppBadgeSize.compact,
                ),
                const SizedBox(width: AppSpacing.s8),
              ],
              Flexible(
                fit: FlexFit.loose,
                child: AppQuietButton(
                  label: running
                      ? l10n.healthBriefingGenerating
                      : l10n.healthBriefingUpdate,
                  onPress: running ? null : onRun,
                  prefix: running
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: FCircularProgress(),
                        )
                      : const Icon(
                          FLucideIcons.refreshCw,
                          size: AppIconSizes.xs,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            r.summary,
            style: typography.md,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(_ago(l10n, r.updatedAt), style: context.captionStyle),
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
    final typography = context.theme.typography;
    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        children: [
          Icon(FLucideIcons.sunset, color: colors.mutedForeground),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.healthBriefingEmpty,
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  l10n.healthBriefingEmptyHint,
                  style: context.captionStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            fit: FlexFit.loose,
            child: AppQuietButton(
              label: running
                  ? l10n.healthBriefingGenerating
                  : l10n.healthBriefingGenerate,
              onPress: running ? null : onRun,
              prefix: running
                  ? const SizedBox(
                      width: AppIconSizes.xs,
                      height: AppIconSizes.xs,
                      child: FCircularProgress(),
                    )
                  : const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
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
