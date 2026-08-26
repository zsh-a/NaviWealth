/// Opik-style trace view: a span **tree + waterfall** with a
/// per-span detail panel.
///
/// **Why a tree + waterfall (vs. the old flat tool-call list).** The
/// previous model lost round structure and timing — it couldn't show
/// that round-2's LLM call ran *after* three tool calls returned, how
/// long each took relative to the turn, or the tokens/model/IO for a
/// given step. Debugging "why is this answer wrong / slow" needs
/// exactly that: hierarchy + timing + payloads. The flat-timeline
/// fallback was removed (no backward-compat); pre-span traces simply
/// show a notice and age out — see `AiTransparencyDetailPage`.
///
/// The persisted model is a flat `List<AiSpan>` + `parentId`;
/// [buildSpanTree] rebuilds the tree (root = the synthesised `turn`
/// span) and flattens it depth-first, children ordered by start.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/visual/visual.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// One flattened row: a span plus its tree depth (for indentation).
typedef SpanRow = ({AiSpan span, int depth});

/// Depth-first flatten. Root is the [AiSpanKind.turn] span (or, if a
/// malformed trace lacks one, every parentless span). Siblings are
/// ordered by `startOffsetMs` so the waterfall reads top-to-bottom in
/// execution order.
List<SpanRow> buildSpanTree(List<AiSpan> spans) {
  final byParent = <String?, List<AiSpan>>{};
  final ids = {for (final s in spans) s.id};
  for (final s in spans) {
    // Treat a dangling parent as a root so nothing is dropped.
    final key = (s.parentId != null && ids.contains(s.parentId))
        ? s.parentId
        : null;
    (byParent[key] ??= <AiSpan>[]).add(s);
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.startOffsetMs.compareTo(b.startOffsetMs));
  }
  final out = <SpanRow>[];
  void walk(AiSpan s, int depth) {
    out.add((span: s, depth: depth));
    for (final child in byParent[s.id] ?? const <AiSpan>[]) {
      walk(child, depth + 1);
    }
  }

  for (final root in byParent[null] ?? const <AiSpan>[]) {
    walk(root, 0);
  }
  return out;
}

class AiTraceWaterfall extends StatefulWidget {
  const AiTraceWaterfall({super.key, required this.trace});

  final AiTrace trace;

  @override
  State<AiTraceWaterfall> createState() => _AiTraceWaterfallState();
}

class _AiTraceWaterfallState extends State<AiTraceWaterfall> {
  String? _selectedId;
  late List<SpanRow> _rows;
  late Map<String, AiSpan> _spansById;
  late int _scaleMs;

  @override
  void initState() {
    super.initState();
    _rebuildLayoutModel();
  }

  @override
  void didUpdateWidget(covariant AiTraceWaterfall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trace != widget.trace) {
      _selectedId = null;
      _rebuildLayoutModel();
    }
  }

  void _rebuildLayoutModel() {
    final rows = buildSpanTree(widget.trace.spans);
    var scale = widget.trace.totalDurationMs;
    for (final r in rows) {
      if (r.span.endOffsetMs > scale) scale = r.span.endOffsetMs;
    }
    _rows = rows;
    _spansById = {for (final r in rows) r.span.id: r.span};
    _scaleMs = scale <= 0 ? 1 : scale;
  }

  @override
  Widget build(BuildContext context) {
    // Span tree construction and scale calculation are intentionally kept
    // out of build. Selecting a row only changes the inspector; it must not
    // re-sort and re-walk every span in the trace on each tap.
    final selected = _selectedId == null ? null : _spansById[_selectedId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RollupHeader(trace: widget.trace),
        const SizedBox(height: AppSpacing.s16),
        for (final r in _rows)
          _WaterfallRow(
            row: r,
            scaleMs: _scaleMs,
            selected: r.span.id == _selectedId,
            onTap: () => setState(
              () => _selectedId = r.span.id == _selectedId ? null : r.span.id,
            ),
          ),
        if (selected != null) ...[
          const SizedBox(height: AppSpacing.s16),
          _SpanDetail(span: selected),
        ],
      ],
    );
  }
}

// ===========================================================================
// Rollup header — the Opik trace-summary strip.
// ===========================================================================

class _RollupHeader extends StatelessWidget {
  const _RollupHeader({required this.trace});
  final AiTrace trace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tok = trace.tokenTotals;
    final cost = estimateTraceCostCny(trace);
    return Wrap(
      spacing: AppSpacing.s6,
      runSpacing: AppSpacing.s6,
      children: [
        AiPill(label: '${trace.totalDurationMs} ms'),
        AiPill(label: l10n.aiTraceRoundsCount(trace.llmRoundCount)),
        AiPill(label: l10n.aiTransparencyToolsCount(trace.toolSpans.length)),
        if (tok.total > 0) AiPill(label: '${_compact(tok.total)} tok'),
        if (tok.cacheRead > 0)
          AiPill(label: 'cacheR ${_compact(tok.cacheRead)}'),
        if (cost != null) AiPill(label: '≈¥${cost.toStringAsFixed(4)}'),
        if (trace.errorSpanCount > 0)
          AiPill(
            label: l10n.aiTransparencyErrors(trace.errorSpanCount),
            state: AiPillState.error,
          ),
      ],
    );
  }
}

// ===========================================================================
// One waterfall row.
// ===========================================================================

class _WaterfallRow extends StatelessWidget {
  const _WaterfallRow({
    required this.row,
    required this.scaleMs,
    required this.selected,
    required this.onTap,
  });

  final SpanRow row;
  final int scaleMs;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final span = row.span;
    final tone = _kindTone(context, span);
    final label = _shortName(span);
    return AppTappable(
      onPress: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? AiTone.surfaceTint(context).withValues(alpha: AppOpacity.scrim)
              : null,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s4,
          horizontal: AppSpacing.s4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Tree label column (indented by depth).
            SizedBox(
              width: AppControlWidths.traceTreeLabel,
              child: Padding(
                padding: EdgeInsets.only(left: AppSpacing.s10 * row.depth),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s6),
                    Expanded(
                      child: Text(
                        label,
                        style: selected
                            ? AiType.metaStrong(context)
                            : AiType.meta(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            // Waterfall bar.
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final left = (span.startOffsetMs / scaleMs * w).clamp(0.0, w);
                  final barW = (span.durationMs / scaleMs * w).clamp(
                    3.0,
                    w - left < 3 ? 3.0 : w - left,
                  );
                  return Stack(
                    children: [
                      Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: AiTone.outline(
                            context,
                          ).withValues(alpha: AppOpacity.medium),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(left: left),
                        child: Container(
                          height: 14,
                          width: barW,
                          decoration: BoxDecoration(
                            color: tone.withValues(
                              alpha: span.isError
                                  ? AppOpacity.overlay
                                  : AppOpacity.prominent,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            SizedBox(
              width: AppControlWidths.traceDuration,
              child: Text(
                '${span.durationMs}ms',
                style: AiType.meta(
                  context,
                ).copyWith(color: AiTone.muted(context)),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Span detail panel — the Opik right-hand inspector.
// ===========================================================================

class _SpanDetail extends StatelessWidget {
  const _SpanDetail({required this.span});
  final AiSpan span;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tok = span.tokens;
    final isPayloadKind =
        span.kind == AiSpanKind.tool || span.kind == AiSpanKind.llm;
    return Container(
      width: double.infinity,
      padding: AppPageRhythm.densePadding,
      decoration: BoxDecoration(
        color: AiTone.surfaceTint(context).withValues(alpha: AppOpacity.muted),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AiTone.outline(context).withValues(alpha: AppOpacity.disabled),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _kindIcon(span),
                size: AppIconSizes.xs,
                color: _kindTone(context, span),
              ),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(span.name, style: AiType.bodyStrong(context)),
              ),
              AiPill(
                label: span.status.wire,
                state: span.isError ? AiPillState.error : AiPillState.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          _kv(context, 'kind', span.kind.wire),
          _kv(context, 'duration', '${span.durationMs} ms'),
          _kv(
            context,
            'window',
            '+${span.startOffsetMs}ms → +${span.endOffsetMs}ms',
          ),
          if (span.model != null) _kv(context, 'model', span.model!),
          if (span.stopReason != null) _kv(context, 'stop', span.stopReason!),
          if (tok != null)
            _kv(
              context,
              'tokens',
              'in ${tok.input} · out ${tok.output} · '
                  'cacheR ${tok.cacheRead} · cacheW ${tok.cacheWrite}',
            ),
          if (span.errorCode != null || span.errorMessage != null)
            _kv(
              context,
              'error',
              [
                span.errorCode,
                span.errorMessage,
              ].where((e) => e != null).join(' · '),
              tone: AiTone.error(context),
            ),
          if (span.input != null) ...[
            const SizedBox(height: AppSpacing.s10),
            AiJsonView(value: span.input, label: 'input'),
          ],
          if (span.output != null) ...[
            const SizedBox(height: AppSpacing.s10),
            AiJsonView(value: span.output, label: 'output'),
          ],
          if (span.attributes != null && span.attributes!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s10),
            AiJsonView(value: span.attributes, label: 'attributes'),
          ],
          if (isPayloadKind && span.input == null && span.output == null) ...[
            const SizedBox(height: AppSpacing.s10),
            Text(
              l10n.aiTraceNoPayloadCaptured,
              style: AiType.meta(
                context,
              ).copyWith(color: AiTone.muted(context)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {Color? tone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppControlWidths.traceDetailKey,
            child: Text(
              k,
              style: AiType.meta(
                context,
              ).copyWith(color: AiTone.muted(context)),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: AiType.meta(
                context,
              ).copyWith(fontFamily: 'monospace', color: tone),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Shared visual helpers + cost model.
// ===========================================================================

Color _kindTone(BuildContext context, AiSpan span) {
  if (span.isError) return AiTone.error(context);
  return switch (span.kind) {
    AiSpanKind.turn => AiTone.active(context),
    AiSpanKind.llm => AiTone.active(context),
    AiSpanKind.tool => AiTone.muted(context),
  };
}

IconData _kindIcon(AiSpan span) => switch (span.kind) {
  AiSpanKind.turn => FLucideIcons.flag,
  AiSpanKind.llm => FLucideIcons.sparkles,
  AiSpanKind.tool => FLucideIcons.zap,
};

String _shortName(AiSpan span) {
  final n = span.name;
  if (n.startsWith('tool:')) return n.substring(5);
  if (n.startsWith('llm:')) return n.substring(4);
  return n;
}

String _compact(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '${(n / 1000000).toStringAsFixed(2)}M';
}

/// Rough CNY cost estimate from the per-LLM-span token totals.
///
/// Rates are **approximate, per-1M-token, hardcoded** — providers
/// change pricing and the user may point at a gateway with custom
/// rates, so this is a debugging aid, never billing truth. Unknown
/// model ⇒ `null` (no cost chip shown rather than a wrong number).
double? estimateTraceCostCny(AiTrace trace) {
  final tok = trace.tokenTotals;
  if (tok.total == 0) return null;
  final model = trace.llmSpans
      .map((s) => s.model)
      .firstWhere((m) => m != null && m.isNotEmpty, orElse: () => null);
  final rate = _rateFor(model);
  if (rate == null) return null;
  return (tok.input * rate.$1 +
          tok.output * rate.$2 +
          tok.cacheRead * rate.$3 +
          tok.cacheWrite * rate.$1) /
      1000000.0;
}

/// (inputPer1M, outputPer1M, cacheReadPer1M) in CNY. Coarse USD→CNY
/// at ~7.2; matched by substring so dated model ids still resolve.
(double, double, double)? _rateFor(String? model) {
  if (model == null) return null;
  final m = model.toLowerCase();
  if (m.contains('opus')) return (108.0, 540.0, 10.8);
  if (m.contains('haiku')) return (5.8, 28.8, 0.58);
  if (m.contains('sonnet')) return (21.6, 108.0, 2.16);
  return null;
}
