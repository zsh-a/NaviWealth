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

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/trace/providers.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/ai/write/drift_undo_stack.dart';
import '../../../core/ai/write/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'ai_trace_timeline.dart';

// ===========================================================================
// List page.
// ===========================================================================

class AiTransparencyPage extends ConsumerWidget {
  const AiTransparencyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracesAsync = ref.watch(recentAiTracesProvider);
    return FScaffold(
      header: const FHeader.nested(title: Text('AI 透明度')),
      childPad: false,
      child: CustomScrollView(
        slivers: <Widget>[
          const SliverToBoxAdapter(child: _UndoSection()),
          tracesAsync.when(
            data: (traces) {
              if (traces.isEmpty) {
                return const SliverToBoxAdapter(child: _EmptyState());
              }
              return SliverList.separated(
                itemCount: traces.length,
                separatorBuilder: (_, _) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: FDivider(),
                ),
                itemBuilder: (context, i) => _TraceRow(trace: traces[i]),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(child: FCircularProgress()),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Text('加载失败: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

/// §5.10.5 — pending-undo section. Lists every persisted entry in
/// [DriftUndoStack] and exposes per-row "撤销" buttons. Tapping
/// [DriftUndoStack.take] removes the entry from the stack (the
/// reverter dispatch that actually rolls the data back is intentional
/// future work — see [PersistentUndoBanner._handleUndo]).
class _UndoSection extends ConsumerWidget {
  const _UndoSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(undoEntriesStreamProvider);
    final colors = context.theme.colors;
    final entries = entriesAsync.value ?? const <PersistedUndoEntry>[];
    final now = DateTime.now().toUtc();
    final live = entries
        .where((e) => e.expiresAt == null || e.expiresAt!.isAfter(now))
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              l10n.aiTransparencyUndoSectionTitle,
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.mutedForeground,
              ),
            ),
          ),
          if (live.isEmpty)
            SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                l10n.aiTransparencyUndoEmpty,
                style: context.theme.typography.xs.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            )
          else
            SoftCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < live.length; i++) ...<Widget>[
                    if (i > 0) const FDivider(),
                    _UndoRow(entry: live[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _UndoRow extends ConsumerWidget {
  const _UndoRow({required this.entry});
  final PersistedUndoEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final summary = entry.payload['summary_zh'] as String? ??
        entry.payload['summaryZh'] as String? ??
        entry.kind;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          const AiSparkle(),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  summary,
                  style: context.theme.typography.sm.copyWith(
                    color: colors.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.expiresAt != null)
                  Text(
                    entry.kind,
                    style: context.theme.typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AiPill(
            label: l10n.aiTransparencyUndoAction,
            state: AiPillState.selected,
            onTap: () async {
              final stack = ref.read(undoStackProvider);
              if (stack == null) return;
              await stack.take(entry.token);
            },
          ),
        ],
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
        style: context.theme.typography.sm.copyWith(
          color: context.theme.colors.mutedForeground,
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
    final title = _displayTitle(trace);
    final source = _displaySource(trace);
    final isError = trace.terminalReason != TerminalReason.done;
    return FTappable(
      onPress: () => context.goNamed(
        AppRouteNames.aiTransparencyDetail,
        pathParameters: <String, String>{'requestId': trace.requestId},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _StatusDot(
                error: isError,
                color: isError ? AiTone.error(context) : AiTone.active(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AiType.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (source != null)
                        AiPill(label: source, state: AiPillState.selected),
                      AiPill(label: '${trace.totalDurationMs} ms'),
                      AiPill(label: trace.backend.wire),
                      if (trace.toolCalls.isNotEmpty)
                        AiPill(label: '工具 ${trace.toolCalls.length}'),
                      if (trace.staleReadModels > 0)
                        AiPill(label: '过期 x${trace.staleReadModels}'),
                      if (isError)
                        AiPill(
                          label: trace.terminalReason.wire,
                          state: AiPillState.error,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _shortTimestamp(trace.startedAtIso),
              style: AiType.meta(context),
            ),
          ],
        ),
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
    return objType != null && objType.isNotEmpty
        ? '$source · $objType'
        : source;
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
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
    return FScaffold(
      header: const FHeader.nested(title: Text('调用链路')),
      childPad: false,
      child: traceAsync.when(
        data: (trace) {
          if (trace == null) {
            return const Center(child: Text('未找到该次调用记录'));
          }
          return _TraceTimelineBody(trace: trace);
        },
        loading: () => const Center(child: FCircularProgress()),
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
    final intent = trace.invocation?['intent']?.toString();
    final title = intent ?? trace.intent.label ?? '(unnamed turn)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AiSparkle(),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: AiType.title(context))),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$eventCount 个事件 · 始于 ${_longTimestamp(trace.startedAtIso)}',
          style: AiType.meta(context),
        ),
        const SizedBox(height: 6),
        Text(
          'request_id ${trace.requestId}',
          style: AiType.meta(context).copyWith(fontFamily: 'monospace'),
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
