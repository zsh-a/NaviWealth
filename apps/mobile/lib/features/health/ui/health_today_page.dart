/// HealthOS Today surface (`docs/healthos-domain.md` §8, D-2.5b
/// follow-up).
///
/// Renders the most recent Morning Briefing as the headline card with
/// a `Run now` affordance underneath. The Briefing is the only signal
/// HealthOS surfaces in-app today; Trend and Plan tabs keep the
/// placeholder until later milestones flesh them out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/contracts/memory_record.dart';
import '../../../design_system/design_system.dart';
import '../agents/providers.dart' as health_agent_providers;
import '../domain/health_metric.dart';
import 'health_today_providers.dart';

class HealthTodayPage extends ConsumerWidget {
  const HealthTodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final briefingAsync = ref.watch(
      health_agent_providers.latestMorningBriefingProvider,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('今日 · HealthOS')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s16),
          children: [
            const _MetricGrid(),
            const SizedBox(height: AppSpacing.s16),
            briefingAsync.when(
              loading: () => const _BriefingSkeleton(),
              error: (e, _) => _BriefingError(message: '$e'),
              data: (record) => _BriefingCard(record: record),
            ),
            const SizedBox(height: AppSpacing.s16),
            const _RunNowSection(),
          ],
        ),
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
    final workout = ref.watch(latestWorkoutProvider);
    final recovery = ref.watch(recoverySignalProvider);
    final steps = ref.watch(latestStepsProvider);
    final energy = ref.watch(latestActiveEnergyProvider);

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _SleepCard(async: sleep)),
            const SizedBox(width: AppSpacing.s8),
            Expanded(child: _HrvCard(async: hrv)),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Expanded(child: _RecoveryCard(async: recovery)),
            const SizedBox(width: AppSpacing.s8),
            Expanded(child: _WorkoutCard(async: workout)),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Expanded(child: _StepsCard(async: steps)),
            const SizedBox(width: AppSpacing.s8),
            Expanded(child: _ActiveEnergyCard(async: energy)),
          ],
        ),
      ],
    );
  }
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.async});
  final AsyncValue<HealthMetric?> async;

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      icon: Icons.nightlight_outlined,
      label: '睡眠',
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          final hours = _secondsToHours(m.value, m.unit);
          return _ValueBig(value: '${_round(hours)}h', sub: _ago(m.capturedAt));
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
    return _MetricCard(
      icon: Icons.favorite_outline,
      label: 'HRV',
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${_round(m.value)} ${m.unit}',
            sub: _ago(m.capturedAt),
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
    return _MetricCard(
      icon: Icons.directions_run,
      label: '运动',
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          final minutes = (m.value / 60).round();
          return _ValueBig(
            value: '${minutes}min',
            sub: _ago(m.capturedAt),
          );
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
    final walking = ref.watch(latestWalkingDistanceProvider);
    return _MetricCard(
      icon: Icons.directions_walk,
      label: '步数',
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
              ? '${(wm.value / 1000.0).toStringAsFixed(1)} km · ${_ago(m.capturedAt)}'
              : _ago(m.capturedAt);
          return _ValueBig(
            value: _formatSteps(m.value),
            sub: sub,
          );
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
    return _MetricCard(
      icon: Icons.local_fire_department_outlined,
      label: '能量',
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (m) {
          if (m == null) return const _ValueDash();
          return _ValueBig(
            value: '${m.value.round()} kcal',
            sub: _ago(m.capturedAt),
          );
        },
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({required this.async});
  final AsyncValue<Map<String, Object?>?> async;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _MetricCard(
      icon: Icons.bolt_outlined,
      label: '恢复',
      child: async.when(
        loading: () => const _ValueSkeleton(),
        error: (e, _) => const _ValueDash(),
        data: (out) {
          if (out == null) return const _ValueDash();
          final verdict = out['verdict']?.toString() ?? 'insufficient_data';
          final score = out['score'];
          final scoreText = score == null ? '—' : '$score';
          return _ValueBig(
            value: scoreText,
            sub: _verdictLabel(verdict),
            subColor: _verdictColor(verdict, scheme),
          );
        },
      ),
    );
  }

  static String _verdictLabel(String v) => switch (v) {
        'rested' => '充分恢复',
        'balanced' => '平衡',
        'strained' => '过载',
        _ => '数据不足',
      };

  static Color _verdictColor(String v, ColorScheme scheme) => switch (v) {
        'rested' => scheme.primary,
        'balanced' => scheme.onSurfaceVariant,
        'strained' => scheme.error,
        _ => scheme.onSurfaceVariant,
      };
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.s4),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            child,
          ],
        ),
      ),
    );
  }
}

class _ValueBig extends StatelessWidget {
  const _ValueBig({required this.value, required this.sub, this.subColor});
  final String value;
  final String sub;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          sub,
          style: textTheme.bodySmall
              ?.copyWith(color: subColor ?? scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ValueDash extends StatelessWidget {
  const _ValueDash();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('—', style: textTheme.titleLarge?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          '暂无数据',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ValueSkeleton extends StatelessWidget {
  const _ValueSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 20,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 40,
          height: 10,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
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

String _utcDayKey(DateTime t) =>
    t.toUtc().toIso8601String().substring(0, 10);

String _formatSteps(double v) {
  final n = v.round();
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _ago(DateTime when) {
  final now = DateTime.now();
  final diff = now.difference(when.toLocal());
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  final days = diff.inDays;
  if (days == 1) return '昨天';
  if (days < 7) return '$days 天前';
  final local = when.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  return '$mm-$dd';
}

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({required this.record});

  final MemoryRecord? record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    if (r == null) return const _BriefingEmpty();
    final outcome = r.payload['outcome'];
    final source = outcome is Map<String, Object?>
        ? outcome['synthesis_source']
        : null;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wb_sunny_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  '早间简报',
                  style: textTheme.titleSmall,
                ),
                const Spacer(),
                if (source is String && source.isNotEmpty)
                  _SourcePill(source: source),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              r.summary,
              style: textTheme.bodyLarge,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              _formatRelative(r.updatedAt),
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _BriefingEmpty extends StatelessWidget {
  const _BriefingEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Row(
          children: [
            Icon(Icons.wb_twilight_outlined, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('暂无简报', style: textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    '点击下方"立即生成简报"以生成今日简报。',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BriefingSkeleton extends StatelessWidget {
  const _BriefingSkeleton();

  @override
  Widget build(BuildContext context) {
    return FCard(
      child: const Padding(
        padding: EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 18,
              child: LinearProgressIndicator(minHeight: 2),
            ),
            SizedBox(height: AppSpacing.s12),
            Text('加载中…'),
          ],
        ),
      ),
    );
  }
}

class _BriefingError extends StatelessWidget {
  const _BriefingError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.error),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(
                '简报加载失败：$message',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = source == 'llm' ? 'LLM' : '自动';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RunNowSection extends ConsumerStatefulWidget {
  const _RunNowSection();

  @override
  ConsumerState<_RunNowSection> createState() => _RunNowSectionState();
}

class _RunNowSectionState extends ConsumerState<_RunNowSection> {
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(_running ? '生成中…' : '立即生成简报'),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            _errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

String _formatRelative(DateTime when) {
  final now = DateTime.now();
  final diff = now.difference(when.toLocal());
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  final days = diff.inDays;
  if (days == 1) return '昨天';
  if (days < 7) return '$days 天前';
  final local = when.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  return '${local.year}-$mm-$dd';
}
