/// AI Transparency surface.
///
/// Two pages:
///   - [AiTransparencyPage] — newest-first list of recent traces, one
///     compact row per turn. The row carries the chips that matter
///     most for quick scanning (backend, duration, terminal reason,
///     tool count, stale count).
///   - [AiTransparencyDetailPage] — vertical **timeline** of the
///     selected trace's call chain. Replaces the old flat-section
///     layout: see `ai_trace_timeline.dart` for the event model.
///
/// The list page intentionally stays thin so the detail page does the
/// heavy lifting. Adding a new event type to a turn requires zero
/// changes here (timeline builder takes care of it).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/trace/providers.dart';
import 'ai_trace_timeline.dart';

// ===========================================================================
// List page.
// ===========================================================================

class AiTransparencyPage extends ConsumerWidget {
  const AiTransparencyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracesAsync = ref.watch(recentAiTracesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AI 透明度')),
      body: tracesAsync.when(
        data: (traces) {
          if (traces.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: traces.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, i) => _TraceRow(trace: traces[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        '暂无 AI 调用记录。\n下次发起对话后，会在此处看到完整轨迹。',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

class _TraceRow extends StatelessWidget {
  const _TraceRow({required this.trace});
  final AiTrace trace;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final title = _displayTitle(trace);
    final source = _displaySource(trace);
    final isError = trace.terminalReason != TerminalReason.done;
    return ListTile(
      leading: _StatusDot(error: isError, color: isError ? cs.error : cs.primary),
      title: Text(
        title,
        style: ts.bodyLarge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (source != null) _Chip(label: source, tone: cs.primary),
            _Chip(label: '${trace.totalDurationMs} ms'),
            _Chip(label: trace.backend.wire),
            if (trace.toolCalls.isNotEmpty)
              _Chip(
                label: '🔧 ${trace.toolCalls.length}',
                tone: cs.outline,
              ),
            if (trace.staleReadModels > 0)
              _Chip(
                label: '过期 ×${trace.staleReadModels}',
                tone: cs.tertiary,
              ),
            if (isError)
              _Chip(label: trace.terminalReason.wire, tone: cs.error),
          ],
        ),
      ),
      trailing: Text(
        _shortTimestamp(trace.startedAtIso),
        style: ts.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      onTap: () => context.goNamed(
        AppRouteNames.aiTransparencyDetail,
        pathParameters: <String, String>{'requestId': trace.requestId},
      ),
    );
  }

  /// Prefer the invocation intent (Wave 33) → falls back to the
  /// intent label → finally a generic placeholder. The invocation
  /// intent is more user-actionable ("explain_change" tells you *what*
  /// the turn was for, while `label` is often the chat tab's
  /// auto-generated title).
  static String _displayTitle(AiTrace trace) {
    final intent = trace.invocation?['intent']?.toString();
    if (intent != null && intent.isNotEmpty) return intent;
    final label = trace.intent.label;
    if (label != null && label.isNotEmpty) return label;
    return '(unnamed turn)';
  }

  /// "expense_detail · exp_123" — present only when the trace was
  /// triggered via an `AiIntentInvocation`. Manual chat-tab turns omit
  /// this chip entirely.
  static String? _displaySource(AiTrace trace) {
    final source = trace.invocation?['source']?.toString();
    if (source == null || source.isEmpty) return null;
    final objType = trace.invocation?['object_type']?.toString();
    return objType != null && objType.isNotEmpty ? '$source · $objType' : source;
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.error, required this.color});
  final bool error;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.tone});
  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = tone ?? cs.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

// ===========================================================================
// Detail page (timeline).
// ===========================================================================

class AiTransparencyDetailPage extends ConsumerWidget {
  const AiTransparencyDetailPage({super.key, required this.requestId});
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traceAsync = ref.watch(aiTraceByIdProvider(requestId));
    return Scaffold(
      appBar: AppBar(title: const Text('调用链路')),
      body: traceAsync.when(
        data: (trace) {
          if (trace == null) {
            return const Center(child: Text('未找到该次调用记录'));
          }
          return _TraceTimelineBody(trace: trace);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _TraceTimelineBody extends StatelessWidget {
  const _TraceTimelineBody({required this.trace});
  final AiTrace trace;

  @override
  Widget build(BuildContext context) {
    final events = buildTimeline(trace);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _HeaderSummary(trace: trace, eventCount: events.length),
        const SizedBox(height: 20),
        AiTraceTimeline(events: events),
      ],
    );
  }
}

/// Compact summary above the timeline. Mirrors the list-row chips
/// plus the request id (so users reporting bugs can quote it).
class _HeaderSummary extends StatelessWidget {
  const _HeaderSummary({required this.trace, required this.eventCount});
  final AiTrace trace;
  final int eventCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final intent = trace.invocation?['intent']?.toString();
    final title = intent ?? trace.intent.label ?? '(unnamed turn)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: ts.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '$eventCount 个事件 · 始于 ${_longTimestamp(trace.startedAtIso)}',
          style: ts.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SelectableText(
          'request_id ${trace.requestId}',
          style: ts.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

String _shortTimestamp(String iso) {
  if (iso.length < 16) return iso;
  return iso.substring(5, 16).replaceFirst('T', ' ');
}

String _longTimestamp(String iso) {
  if (iso.length < 19) return iso;
  return iso.substring(0, 19).replaceFirst('T', ' ');
}
