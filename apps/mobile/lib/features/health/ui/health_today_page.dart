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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as health_agent_providers;
import '../data/health_sync_service.dart';
import '../data/providers.dart' as health_data;
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'body_measurement_entry_sheet.dart';
import 'health_today_providers.dart';

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
          onPress: () => showBodyMeasurementEntrySheet(
            context: context,
            initialKind: HealthMetricKind.weight,
          ),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: const [
          _HealthDataStatusNotice(),
          SizedBox(height: AppSpacing.s12),
          _RecoveryHero(),
          SizedBox(height: AppSpacing.s12),
          _MetricGrid(),
          SizedBox(height: AppSpacing.s12),
          _BriefingPanel(),
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
              errorMessage: '权限被拒绝',
            );
          });
          return;
        }
      }
      final result = await service.syncRange();
      setState(() => _lastResult = result);
      ref
        ..invalidate(latestSleepSessionProvider)
        ..invalidate(latestHrvProvider)
        ..invalidate(latestHeartRateProvider)
        ..invalidate(latestWorkoutProvider)
        ..invalidate(latestStepsProvider)
        ..invalidate(latestWalkingDistanceProvider)
        ..invalidate(latestActiveEnergyProvider)
        ..invalidate(recoverySignalProvider);
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
    final text = !enabled
        ? 'HealthOS 未启用'
        : _running
        ? '正在同步健康数据…'
        : result == null
        ? '同步最近 30 天健康数据'
        : result.ok
        ? '已同步 ${result.upserted} 新数据 · ${result.unchanged} 未变'
        : result.errorMessage ?? '同步失败';
    final action = !enabled
        ? null
        : FButton(
            variant: FButtonVariant.outline,
            onPress: _running ? null : _sync,
            prefix: _running
                ? const SizedBox(
                    width: AppIconSizes.xs,
                    height: AppIconSizes.xs,
                    child: FCircularProgress(),
                  )
                : const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
            child: Text(_running ? '同步中' : '同步'),
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
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: async.when(
        loading: () => const SizedBox(
          height: 96,
          child: Center(child: FCircularProgress()),
        ),
        error: (e, _) => Text(
          '恢复状态加载失败：$e',
          style: typography.xs.copyWith(color: colors.destructive),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        data: (out) {
          final verdict = out?['verdict']?.toString() ?? 'insufficient_data';
          final score = out?['score'];
          final scoreText = score == null ? '—' : '$score';
          final color = _RecoveryTone.color(verdict, colors);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _RecoveryTone.icon(verdict),
                    color: color,
                    size: AppIconSizes.md,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      '今日恢复',
                      style: typography.sm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(scoreText, style: typography.xl.copyWith(color: color)),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                _RecoveryTone.label(verdict),
                style: typography.xl.copyWith(color: color),
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                _RecoveryTone.suggestion(verdict),
                style: typography.sm.copyWith(color: colors.mutedForeground),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricGrid extends ConsumerWidget {
  const _MetricGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleep = ref.watch(latestSleepSessionProvider);
    final hrv = ref.watch(latestHrvProvider);
    final heartRate = ref.watch(latestHeartRateProvider);
    final workout = ref.watch(latestWorkoutProvider);
    final steps = ref.watch(latestStepsProvider);
    final energy = ref.watch(latestActiveEnergyProvider);
    final cards = <Widget>[
      _SleepCard(async: sleep),
      _HrvCard(async: hrv),
      _HeartRateCard(async: heartRate),
      _StepsCard(async: steps),
      _WorkoutCard(async: workout),
      _ActiveEnergyCard(async: energy),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= Breakpoints.contentThreeColumn
            ? 3
            : 2;
        const gap = AppSpacing.s8;
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += columns) {
          final end = math.min(i + columns, cards.length);
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = i; j < end; j++) ...[
                  if (j > i) const SizedBox(width: gap),
                  Expanded(child: cards[j]),
                ],
                for (var j = end; j < i + columns; j++) ...[
                  const SizedBox(width: gap),
                  const Spacer(),
                ],
              ],
            ),
          );
          if (end < cards.length) rows.add(const SizedBox(height: gap));
        }
        return Column(children: rows);
      },
    );
  }
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.moon,
      label: l10n.healthSleepMetricLabel,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          final hours = _secondsToHours(m.value, m.unit);
          return _ValueBig(value: '${_round(hours)}h', sub: _ago(l10n, m.capturedAt));
        },
      ),
    );
  }
}

class _HrvCard extends StatelessWidget {
  const _HrvCard({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.heartPulse,
      label: l10n.healthHrvMetricLabel,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)} ${m.unit}',
            sub: _ago(l10n, m.capturedAt),
          );
        },
      ),
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.heartPulse,
      label: l10n.healthHeartRateMetricLabel,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)} ${m.unit}',
            sub: _ago(l10n, m.capturedAt),
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
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          final minutes = (m.value / 60).round();
          return _ValueBig(value: '${minutes}min', sub: _ago(l10n, m.capturedAt));
        },
      ),
    );
  }
}

class _StepsCard extends ConsumerWidget {
  const _StepsCard({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final walking = ref.watch(latestWalkingDistanceProvider);
    return _MetricCard(
      icon: FLucideIcons.footprints,
      label: l10n.healthStepsMetricLabel,
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
          return _ValueBig(value: _formatSteps(m.value), sub: sub);
        },
      ),
    );
  }
}

class _ActiveEnergyCard extends StatelessWidget {
  const _ActiveEnergyCard({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MetricCard(
      icon: FLucideIcons.flame,
      label: l10n.healthEnergyMetricLabel,
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${m.value.round()} kcal',
            sub: _ago(l10n, m.capturedAt),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.child,
  });
  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: AppIconSizes.sm, color: colors.mutedForeground),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: typography.xs.copyWith(color: colors.mutedForeground),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          child,
        ],
      ),
    );
  }
}

class _ValueBig extends StatelessWidget {
  const _ValueBig({required this.value, required this.sub});
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: typography.xl),
        const SizedBox(height: AppSpacing.s2),
        Text(sub, style: typography.xs.copyWith(color: colors.mutedForeground)),
      ],
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
        Text('—', style: typography.xl.copyWith(color: colors.mutedForeground)),
        const SizedBox(height: AppSpacing.s2),
        Text(
          '暂无数据',
          style: typography.xs.copyWith(color: colors.mutedForeground),
        ),
      ],
    );
  }
}

class _ValueSkeleton extends StatelessWidget {
  const _ValueSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 20,
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        Container(
          width: 40,
          height: 10,
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
      ],
    );
  }
}

class _RecoveryTone {
  const _RecoveryTone._();

  static IconData icon(String v) => switch (v) {
    'rested' => FLucideIcons.zap,
    'balanced' => FLucideIcons.activity,
    'strained' => FLucideIcons.triangleAlert,
    _ => FLucideIcons.info,
  };

  static Color color(String v, FColors colors) => switch (v) {
    'rested' => colors.primary,
    'balanced' => colors.mutedForeground,
    'strained' => colors.destructive,
    _ => colors.mutedForeground,
  };

  static String label(String v) => switch (v) {
    'rested' => '充分恢复',
    'balanced' => '平衡',
    'strained' => '过载',
    _ => '数据不足',
  };

  static String suggestion(String v) => switch (v) {
    'rested' => '今天可以安排高强度训练或高认知负荷工作。',
    'balanced' => '维持平时节奏，训练和会议都不要推到极限。',
    'strained' => '建议减负：轻量活动、补眠，避免连续高压安排。',
    _ => '先同步并连续记录几天，恢复建议会更稳定。',
  };
}

double _secondsToHours(double value, String unit) => switch (unit) {
  's' => value / 3600.0,
  'min' => value / 60.0,
  'h' => value,
  _ => value / 3600.0,
};

double _round(double v) => (v * 100).round() / 100.0;

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
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.sun,
                size: AppIconSizes.md,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                '早间简报',
                style: typography.sm.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (source is String && source.isNotEmpty)
                AppBadge(
                  label: source == 'llm' ? 'LLM' : '自动',
                  size: AppBadgeSize.compact,
                ),
              const SizedBox(width: AppSpacing.s8),
              FButton(
                variant: FButtonVariant.outline,
                onPress: running ? null : onRun,
                prefix: running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: FCircularProgress(),
                      )
                    : const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
                child: Text(running ? '生成中' : '更新'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            r.summary,
            style: typography.md,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            _ago(l10n, r.updatedAt),
            style: typography.xs.copyWith(color: colors.mutedForeground),
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
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return SoftCard(
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
                  '暂无简报',
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  '同步数据后可生成今日简报。',
                  style: typography.xs.copyWith(color: colors.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.outline,
            onPress: running ? null : onRun,
            prefix: running
                ? const SizedBox(
                    width: AppIconSizes.xs,
                    height: AppIconSizes.xs,
                    child: FCircularProgress(),
                  )
                : const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
            child: Text(running ? '生成中' : '生成'),
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
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.s20, child: FProgress()),
          const SizedBox(height: AppSpacing.s12),
          Text(AppLocalizations.of(context).healthLoadingLabel),
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
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        children: [
          Icon(FLucideIcons.circleAlert, color: colors.destructive),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              '简报加载失败：$message',
              style: typography.xs,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
