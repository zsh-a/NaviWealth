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
      appBar: AppBar(title: const Text('Today · HealthOS')),
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
      label: 'Sleep',
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
      label: 'Workout',
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

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({required this.async});
  final AsyncValue<Map<String, Object?>?> async;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _MetricCard(
      icon: Icons.bolt_outlined,
      label: 'Recovery',
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
        'rested' => 'Rested',
        'balanced' => 'Balanced',
        'strained' => 'Strained',
        _ => 'Not enough data',
      };

  static Color _verdictColor(String v, ColorScheme scheme) => switch (v) {
        'rested' => scheme.primary,
        'balanced' => scheme.outline,
        'strained' => scheme.error,
        _ => scheme.outline,
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
                Icon(icon, size: 16, color: scheme.outline),
                const SizedBox(width: AppSpacing.s4),
                Text(
                  label,
                  style: textTheme.labelMedium?.copyWith(color: scheme.outline),
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
              ?.copyWith(color: subColor ?? scheme.outline),
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
        Text('—', style: textTheme.titleLarge?.copyWith(color: scheme.outline)),
        const SizedBox(height: 2),
        Text(
          'no data',
          style: textTheme.bodySmall?.copyWith(color: scheme.outline),
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

String _ago(DateTime when) {
  final now = DateTime.now();
  final diff = now.difference(when.toLocal());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  final days = diff.inDays;
  if (days == 1) return 'yesterday';
  if (days < 7) return '${days}d ago';
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
                  'Morning Briefing',
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
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              _formatRelative(r.updatedAt),
              style: textTheme.bodySmall?.copyWith(color: scheme.outline),
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
            Icon(Icons.wb_twilight_outlined, color: scheme.outline),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No briefing yet', style: textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'Tap Run now below to generate today\'s briefing.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
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
            Text('Loading…'),
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
                'Briefing unavailable: $message',
                style: Theme.of(context).textTheme.bodySmall,
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
    final label = source == 'llm' ? 'LLM' : 'auto';
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
          label: Text(_running ? 'Running…' : 'Run briefing now'),
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
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  final days = diff.inDays;
  if (days == 1) return 'Yesterday';
  if (days < 7) return '${days}d ago';
  final local = when.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  return '${local.year}-$mm-$dd';
}
