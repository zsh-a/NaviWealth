/// AI Transparency surface.
///
/// Two pages:
///   - [AiTransparencyPage] — newest-first list of recent traces, one
///     compact row per turn. The row carries the chips that matter
///     most for quick scanning (backend, duration, terminal reason,
///     tool count, stale count).
///   - [AiTransparencyDetailPage] — Opik-style **span tree +
///     waterfall** of the selected trace, with a per-span detail
///     panel. See `ai_trace_waterfall.dart`.
///
/// The list page intentionally stays thin so the detail page does the
/// heavy lifting.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/trace/ai_trace_capture_preference.dart';
import '../../../core/ai/trace/providers.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/ai/write/drift_undo_stack.dart';
import '../../../core/ai/write/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'ai_trace_waterfall.dart';

// ===========================================================================
// List page.
// ===========================================================================

class AiTransparencyPage extends ConsumerStatefulWidget {
  const AiTransparencyPage({super.key});

  @override
  ConsumerState<AiTransparencyPage> createState() => _AiTransparencyPageState();
}

class _AiTransparencyPageState extends ConsumerState<AiTransparencyPage> {
  bool _errorsOnly = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tracesAsync = ref.watch(recentAiTracesProvider);
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.settingsAiTransparencyTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: CustomScrollView(
        slivers: <Widget>[
          const SliverToBoxAdapter(child: _UndoSection()),
          const SliverToBoxAdapter(child: _CaptureToggle()),
          tracesAsync.when(
            data: (traces) {
              if (traces.isEmpty) {
                return const SliverToBoxAdapter(child: _EmptyState());
              }
              final shown = _errorsOnly
                  ? traces
                        .where((t) => t.terminalReason != TerminalReason.done)
                        .toList(growable: false)
                  : traces;
              return SliverMainAxisGroup(
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: _AggregateHeader(
                      traces: traces,
                      errorsOnly: _errorsOnly,
                      onToggleErrors: () =>
                          setState(() => _errorsOnly = !_errorsOnly),
                    ),
                  ),
                  if (shown.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.s24),
                        child: Center(
                          child: Text(l10n.aiTransparencyFilteredEmpty),
                        ),
                      ),
                    )
                  else
                    SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppSpacing.s16),
                        child: FDivider(),
                      ),
                      itemBuilder: (context, i) => _TraceRow(trace: shown[i]),
                    ),
                ],
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(child: FCircularProgress()),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Text(l10n.aiTransparencyLoadError('$e'))),
            ),
          ),
        ],
      ),
    );
  }
}

/// Verbose-capture switch. Off (default) = metadata-only spans; on =
/// also persist each step's input/output for deep debugging. Snapshot
/// per turn, so flipping it only affects *future* calls.
class _CaptureToggle extends ConsumerWidget {
  const _CaptureToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final verbose = ref.watch(aiTraceVerboseProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s4, AppSpacing.s16, AppSpacing.s4),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiTransparencyVerboseTitle,
                    style: AiType.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    l10n.aiTransparencyVerboseSubtitle,
                    style: AiType.meta(
                      context,
                    ).copyWith(color: AiTone.muted(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            AiPill(
              label: verbose
                  ? l10n.aiTransparencyToggleOn
                  : l10n.aiTransparencyToggleOff,
              state: verbose ? AiPillState.selected : AiPillState.neutral,
              onTap: () => ref.read(aiTraceVerboseProvider.notifier).toggle(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opik-style aggregate strip over the recent-trace window: volume,
/// error rate, p50/p95 latency, token + cost totals. Doubles as the
/// "errors only" filter toggle.
class _AggregateHeader extends StatelessWidget {
  const _AggregateHeader({
    required this.traces,
    required this.errorsOnly,
    required this.onToggleErrors,
  });

  final List<AiTrace> traces;
  final bool errorsOnly;
  final VoidCallback onToggleErrors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final n = traces.length;
    final errors = traces
        .where((t) => t.terminalReason != TerminalReason.done)
        .length;
    final durations =
        traces.map((t) => t.totalDurationMs).toList(growable: false)..sort();
    final p50 = _pct(durations, 0.50);
    final p95 = _pct(durations, 0.95);
    var tokens = 0;
    var cost = 0.0;
    var hasCost = false;
    for (final t in traces) {
      tokens += t.tokenTotals.total;
      final c = estimateTraceCostCny(t);
      if (c != null) {
        cost += c;
        hasCost = true;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s8, AppSpacing.s16, AppSpacing.s8),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiTransparencyRecentCalls(n),
              style: AiType.body(context).copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AiPill(
                  label: l10n.aiTransparencyErrors(errors),
                  state: errors > 0 && errorsOnly
                      ? AiPillState.error
                      : (errors > 0
                            ? AiPillState.selected
                            : AiPillState.neutral),
                  onTap: errors > 0 ? onToggleErrors : null,
                ),
                AiPill(label: 'p50 ${p50}ms'),
                AiPill(label: 'p95 ${p95}ms'),
                if (tokens > 0) AiPill(label: '$tokens tok'),
                if (hasCost) AiPill(label: '≈¥${cost.toStringAsFixed(3)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static int _pct(List<int> sortedAsc, double q) {
    if (sortedAsc.isEmpty) return 0;
    final idx = ((sortedAsc.length - 1) * q).round();
    return sortedAsc[idx];
  }
}

/// Pending-undo section. Lists every persisted entry in
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s12, AppSpacing.s16, AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.s4, bottom: AppSpacing.s8),
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s14),
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
    final summary =
        entry.payload['summary_zh'] as String? ??
        entry.payload['summaryZh'] as String? ??
        entry.kind;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
      child: Row(
        children: <Widget>[
          const AiSparkle(),
          const SizedBox(width: AppSpacing.s8),
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
          const SizedBox(width: AppSpacing.s8),
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
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Text(
        AppLocalizations.of(context).aiTransparencyEmpty,
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
    final l10n = AppLocalizations.of(context);
    final title = _displayTitle(trace, l10n);
    final source = _displaySource(trace);
    final isError = trace.terminalReason != TerminalReason.done;
    return FTappable(
      onPress: () => context.goNamed(
        AppRouteNames.aiTransparencyDetail,
        pathParameters: <String, String>{'requestId': trace.requestId},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: _StatusDot(
                error: isError,
                color: isError ? AiTone.error(context) : AiTone.active(context),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
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
                  const SizedBox(height: AppSpacing.s6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (source != null)
                        AiPill(label: source, state: AiPillState.selected),
                      AiPill(label: '${trace.totalDurationMs} ms'),
                      AiPill(label: trace.backend.wire),
                      if (trace.hasSpans && trace.tokenTotals.total > 0)
                        AiPill(label: '${trace.tokenTotals.total} tok'),
                      if (trace.toolSpans.isNotEmpty)
                        AiPill(
                          label: l10n.aiTransparencyToolsCount(
                            trace.toolSpans.length,
                          ),
                        ),
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
            const SizedBox(width: AppSpacing.s12),
            Text(
              _shortTimestamp(trace.startedAtIso),
              style: AiType.meta(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Prefer the invocation intent → falls back to the
  /// intent label → finally a generic placeholder. The invocation
  /// intent is more user-actionable ("explain_change" tells you *what*
  /// the turn was for, while `label` is often the chat tab's
  /// auto-generated title).
  static String _displayTitle(AiTrace trace, AppLocalizations l10n) {
    final intent = trace.invocation?['intent']?.toString();
    if (intent != null && intent.isNotEmpty) return intent;
    final label = trace.intent.label;
    if (label != null && label.isNotEmpty) return label;
    return l10n.aiTransparencyUnnamedTurn;
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
        margin: const EdgeInsets.only(top: AppSpacing.s8),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

// ===========================================================================
// Detail page (waterfall).
// ===========================================================================

class AiTransparencyDetailPage extends ConsumerWidget {
  const AiTransparencyDetailPage({super.key, required this.requestId});
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final traceAsync = ref.watch(aiTraceByIdProvider(requestId));
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.aiTransparencyDetailTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: traceAsync.when(
        data: (trace) {
          if (trace == null) {
            return Center(child: Text(l10n.aiTransparencyTraceNotFound));
          }
          return _TraceWaterfallBody(trace: trace);
        },
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) =>
            Center(child: Text(l10n.aiTransparencyLoadError('$e'))),
      ),
    );
  }
}

class _TraceWaterfallBody extends StatelessWidget {
  const _TraceWaterfallBody({required this.trace});
  final AiTrace trace;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s12, AppSpacing.s16, AppSpacing.s24),
      children: [
        _HeaderSummary(trace: trace, eventCount: trace.spans.length),
        const SizedBox(height: AppSpacing.s20),
        if (trace.hasSpans)
          AiTraceWaterfall(trace: trace)
        else
          // Traces written before the span model existed have no
          // call chain to draw (no backward-compat shim — they age
          // out within the 30-day retention window).
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
            child: Text(
              AppLocalizations.of(context).aiTransparencyNoSpans,
              textAlign: TextAlign.center,
              style: AiType.body(
                context,
              ).copyWith(color: AiTone.muted(context)),
            ),
          ),
      ],
    );
  }
}

/// Compact summary above the waterfall. Mirrors the list-row chips
/// plus the request id (so users reporting bugs can quote it).
class _HeaderSummary extends StatelessWidget {
  const _HeaderSummary({required this.trace, required this.eventCount});
  final AiTrace trace;
  final int eventCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final intent = trace.invocation?['intent']?.toString();
    final title =
        intent ?? trace.intent.label ?? l10n.aiTransparencyUnnamedTurn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AiSparkle(),
            const SizedBox(width: AppSpacing.s6),
            Expanded(child: Text(title, style: AiType.title(context))),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          l10n.aiTransparencyEventSummary(
            eventCount,
            _longTimestamp(trace.startedAtIso),
          ),
          style: AiType.meta(context),
        ),
        const SizedBox(height: AppSpacing.s6),
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
