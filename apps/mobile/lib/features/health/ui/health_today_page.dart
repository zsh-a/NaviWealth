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
            briefingAsync.when(
              loading: () => const _BriefingSkeleton(),
              error: (e, _) => _BriefingError(message: '$e'),
              data: (record) => _BriefingCard(record: record),
            ),
            const SizedBox(height: AppSpacing.s16),
            const _RunNowSection(),
            const SizedBox(height: AppSpacing.s24),
            const _ComingSoon(
              icon: Icons.show_chart,
              title: 'Trends',
              subtitle:
                  'Weekly and monthly trend charts arrive once the sync window has enough data.',
            ),
            const SizedBox(height: AppSpacing.s12),
            const _ComingSoon(
              icon: Icons.event_note_outlined,
              title: 'Plan',
              subtitle:
                  'Recovery + load suggestions land alongside the trend view.',
            ),
          ],
        ),
      ),
    );
  }
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

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.outline),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
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
