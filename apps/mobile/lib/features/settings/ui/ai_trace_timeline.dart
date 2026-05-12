/// Timeline view of an [AiTrace]'s call chain.
///
/// **Why a separate module?** The transparency page used to render the
/// trace as a flat list of sections, which lost the *temporal order*
/// of the agent's tool calls. A user staring at "this answer is
/// wrong" needs to see, in order: where the call came from → what
/// route was chosen → which tools the model invoked → what data was
/// fresh / stale → how the turn ended. That's a timeline, not a
/// summary.
///
/// **Extensibility contract**: every row on the page is a
/// [TraceEvent]. Adding a new kind (token usage, reply-chip tap, undo
/// record, model thinking pause) means subclassing [TraceEvent] and
/// updating [buildTimeline]. The widget code doesn't change.
///
/// The current source data is the existing `AiTrace` (Waves 5/6/30/33).
/// `TraceToolCall` doesn't yet carry start timestamps, so we render
/// tool calls in stored order — that's the order the model emitted
/// them and is what the user cares about.
library;

import 'package:flutter/material.dart';

import '../../../core/ai/contracts/contracts.dart';

// ===========================================================================
// Event model (extensible).
// ===========================================================================

/// One row on the trace timeline. Subtypes carry per-event detail and
/// optionally an expanded body that renders below the primary row when
/// the user taps to expand.
sealed class TraceEvent {
  const TraceEvent();

  /// Stable kind identifier used by filter chips. Adding a new event
  /// type requires picking a unique kind and updating the filter
  /// widget's switch.
  TraceEventKind get kind;

  /// Headline shown on the collapsed row. Stay short — wraps at 2 lines.
  String get title;

  /// Optional secondary line under the title (metadata, duration,
  /// status). Empty string means "no second line".
  String get subtitle;

  /// Icon for the timeline marker. Use outline variants — calm
  /// intelligence (§5.6).
  IconData get icon;

  /// Pick the rail / icon tone from the active scheme. Errors return
  /// `cs.error`; normal events fall through to `cs.outline` so the
  /// timeline stays muted.
  Color tone(ColorScheme cs);

  /// When non-null, the row is expandable: tapping shows this body
  /// underneath. Return `null` for events that need no detail (most
  /// of them — keep the page scannable).
  Widget? expandedBody(BuildContext context) => null;
}

enum TraceEventKind {
  invocation,
  routing,
  toolCall,
  disclosure,
  freshnessAlert,
  terminal,
}

class InvocationEvent extends TraceEvent {
  const InvocationEvent({
    required this.source,
    required this.intent,
    this.objectType,
    this.objectId,
    this.contextKeys = const <String>[],
  });

  final String source;
  final String intent;
  final String? objectType;
  final String? objectId;
  final List<String> contextKeys;

  @override
  TraceEventKind get kind => TraceEventKind.invocation;

  @override
  String get title => '触发: $intent';

  @override
  String get subtitle {
    final parts = <String>['来自 $source'];
    if (objectType != null) {
      parts.add('${objectType!}${objectId != null ? ":$objectId" : ""}');
    }
    return parts.join(' · ');
  }

  @override
  IconData get icon => Icons.flag_outlined;

  @override
  Color tone(ColorScheme cs) => cs.primary;

  @override
  Widget? expandedBody(BuildContext context) {
    if (contextKeys.isEmpty) return null;
    return _kvBlock(context, <(String, String)>[
      ('context keys', contextKeys.join(', ')),
    ]);
  }
}

class RoutingEvent extends TraceEvent {
  const RoutingEvent({
    required this.backend,
    required this.budgetTier,
    required this.routingReason,
    required this.capability,
    required this.risk,
    required this.intentLabel,
  });

  final String backend;
  final String budgetTier;
  final String routingReason;
  final String capability;
  final String risk;
  final String? intentLabel;

  @override
  TraceEventKind get kind => TraceEventKind.routing;

  @override
  String get title => '路由: $backend';

  @override
  String get subtitle => '$routingReason · tier=$budgetTier';

  @override
  IconData get icon => Icons.alt_route_outlined;

  @override
  Color tone(ColorScheme cs) => cs.secondary;

  @override
  Widget? expandedBody(BuildContext context) => _kvBlock(context, <(String, String)>[
        ('capability', capability),
        ('risk', risk),
        if (intentLabel != null && intentLabel!.isNotEmpty)
          ('label', intentLabel!),
      ]);
}

class ToolCallEvent extends TraceEvent {
  const ToolCallEvent({
    required this.indexLabel,
    required this.name,
    required this.durationMs,
    required this.ok,
  });

  /// "1/3" form lets the user see chain depth at a glance.
  final String indexLabel;
  final String name;
  final int durationMs;
  final bool ok;

  @override
  TraceEventKind get kind => TraceEventKind.toolCall;

  @override
  String get title => '$indexLabel  $name';

  @override
  String get subtitle => '${durationMs}ms · ${ok ? 'ok' : 'error'}';

  @override
  IconData get icon =>
      ok ? Icons.bolt_outlined : Icons.error_outline;

  @override
  Color tone(ColorScheme cs) => ok ? cs.outline : cs.error;
}

class DisclosureEvent extends TraceEvent {
  const DisclosureEvent({
    required this.purpose,
    required this.fieldsCount,
    required this.rowCount,
    required this.consent,
  });

  final String purpose;
  final int fieldsCount;
  final int rowCount;
  final String consent;

  @override
  TraceEventKind get kind => TraceEventKind.disclosure;

  @override
  String get title => '披露请求: $purpose';

  @override
  String get subtitle => '$rowCount 行 · $fieldsCount 字段 · 同意=$consent';

  @override
  IconData get icon => Icons.lock_outline;

  @override
  Color tone(ColorScheme cs) =>
      consent == 'denied' ? cs.outline : cs.tertiary;
}

class FreshnessAlertEvent extends TraceEvent {
  const FreshnessAlertEvent({required this.readModelNames});

  final List<String> readModelNames;

  @override
  TraceEventKind get kind => TraceEventKind.freshnessAlert;

  @override
  String get title => '数据过期 ×${readModelNames.length}';

  @override
  String get subtitle => '下次对话将强制刷新';

  @override
  IconData get icon => Icons.update_outlined;

  @override
  Color tone(ColorScheme cs) => cs.tertiary;

  @override
  Widget? expandedBody(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final name in readModelNames) _MiniTag(label: name),
        ],
      );
}

class TerminalEvent extends TraceEvent {
  const TerminalEvent({required this.reason, required this.totalDurationMs});

  final String reason;
  final int totalDurationMs;

  @override
  TraceEventKind get kind => TraceEventKind.terminal;

  @override
  String get title => '结束: $reason';

  @override
  String get subtitle => '总耗时 ${totalDurationMs}ms';

  @override
  IconData get icon =>
      reason == 'done' ? Icons.check_circle_outline : Icons.cancel_outlined;

  @override
  Color tone(ColorScheme cs) =>
      reason == 'done' ? cs.primary : cs.error;
}

// ===========================================================================
// Builder.
// ===========================================================================

/// Synthesise a timeline from an [AiTrace]. Order:
///   1. Invocation (if any — Wave 33)
///   2. Routing decision
///   3. Tool calls (in stored order — matches model emission)
///   4. Disclosures (separately, time order not captured)
///   5. Freshness alert (collapsed into one row)
///   6. Terminal
List<TraceEvent> buildTimeline(AiTrace trace) {
  final out = <TraceEvent>[];

  final inv = trace.invocation;
  if (inv != null) {
    out.add(
      InvocationEvent(
        source: inv['source']?.toString() ?? '?',
        intent: inv['intent']?.toString() ?? '?',
        objectType: inv['object_type']?.toString(),
        objectId: inv['object_id']?.toString(),
        contextKeys: switch (inv['context_keys']) {
          final List<Object?> list => list.whereType<String>().toList(),
          _ => const <String>[],
        },
      ),
    );
  }

  out.add(
    RoutingEvent(
      backend: trace.backend.wire,
      budgetTier: trace.budgetTier.wire,
      routingReason: trace.routingReason,
      capability: trace.intent.capability.wire,
      risk: trace.intent.risk.wire,
      intentLabel: trace.intent.label,
    ),
  );

  final total = trace.toolCalls.length;
  for (var i = 0; i < total; i++) {
    final c = trace.toolCalls[i];
    out.add(
      ToolCallEvent(
        indexLabel: '${i + 1}/$total',
        name: c.name,
        durationMs: c.durationMs,
        ok: c.ok,
      ),
    );
  }

  for (final d in trace.disclosures) {
    out.add(
      DisclosureEvent(
        purpose: d.purpose.wire,
        fieldsCount: d.fieldsCount,
        rowCount: d.rowCount,
        consent: d.consent.wire,
      ),
    );
  }

  if (trace.staleReadModels > 0) {
    out.add(
      FreshnessAlertEvent(
        readModelNames: trace.staleReadModelNames.toList(),
      ),
    );
  }

  out.add(
    TerminalEvent(
      reason: trace.terminalReason.wire,
      totalDurationMs: trace.totalDurationMs,
    ),
  );

  return out;
}

// ===========================================================================
// Widget.
// ===========================================================================

class AiTraceTimeline extends StatefulWidget {
  const AiTraceTimeline({super.key, required this.events});

  final List<TraceEvent> events;

  @override
  State<AiTraceTimeline> createState() => _AiTraceTimelineState();
}

class _AiTraceTimelineState extends State<AiTraceTimeline> {
  final Set<int> _expanded = <int>{};
  final Set<TraceEventKind> _activeFilters = <TraceEventKind>{};

  void _toggle(int index) {
    setState(() {
      if (!_expanded.add(index)) _expanded.remove(index);
    });
  }

  void _toggleFilter(TraceEventKind kind) {
    setState(() {
      if (!_activeFilters.add(kind)) _activeFilters.remove(kind);
    });
  }

  List<TraceEvent> get _visibleEvents {
    if (_activeFilters.isEmpty) return widget.events;
    return widget.events.where((e) => _activeFilters.contains(e.kind)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final available = <TraceEventKind>{
      for (final e in widget.events) e.kind,
    };
    final visible = _visibleEvents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (available.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FilterRow(
              available: available,
              active: _activeFilters,
              onToggle: _toggleFilter,
            ),
          ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '当前筛选下没有事件',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (var i = 0; i < visible.length; i++)
            _TimelineRow(
              event: visible[i],
              isFirst: i == 0,
              isLast: i == visible.length - 1,
              expanded: _expanded.contains(i),
              onTap: visible[i].expandedBody(context) == null
                  ? null
                  : () => _toggle(i),
            ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.available,
    required this.active,
    required this.onToggle,
  });

  final Set<TraceEventKind> available;
  final Set<TraceEventKind> active;
  final ValueChanged<TraceEventKind> onToggle;

  String _labelFor(TraceEventKind k) => switch (k) {
        TraceEventKind.invocation => '触发',
        TraceEventKind.routing => '路由',
        TraceEventKind.toolCall => '工具',
        TraceEventKind.disclosure => '披露',
        TraceEventKind.freshnessAlert => '数据过期',
        TraceEventKind.terminal => '结束',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final k in TraceEventKind.values)
            if (available.contains(k))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _PillButton(
                  label: _labelFor(k),
                  selected: active.contains(k),
                  selectedTone: cs.primary,
                  onTap: () => onToggle(k),
                ),
              ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.selected,
    required this.selectedTone,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedTone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? selectedTone.withValues(alpha: 0.16) : Colors.transparent;
    final fg = selected ? selectedTone : cs.onSurfaceVariant;
    return Material(
      color: bg,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? selectedTone : cs.outlineVariant,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.event,
    required this.isFirst,
    required this.isLast,
    required this.expanded,
    required this.onTap,
  });

  final TraceEvent event;
  final bool isFirst;
  final bool isLast;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = event.tone(cs);
    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left rail: vertical line + dot ────────────────────────
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  // Top connector (hidden for the first row).
                  SizedBox(
                    width: 2,
                    height: 14,
                    child: isFirst
                        ? const SizedBox.shrink()
                        : ColoredBox(
                            color: cs.outlineVariant.withValues(alpha: 0.7),
                          ),
                  ),
                  // Marker.
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tone.withValues(alpha: 0.16),
                      border: Border.all(color: tone, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: Icon(event.icon, size: 13, color: tone),
                  ),
                  // Bottom connector (hidden for the last row).
                  Expanded(
                    child: SizedBox(
                      width: 2,
                      child: isLast
                          ? const SizedBox.shrink()
                          : ColoredBox(
                              color: cs.outlineVariant.withValues(alpha: 0.7),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // ── Right: event card ─────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12, right: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (onTap != null)
                          Icon(
                            expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                      ],
                    ),
                    if (event.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.subtitle,
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (expanded) ...[
                      const SizedBox(height: 8),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        child: event.expandedBody(context) ??
                            const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.tertiary,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

Widget _kvBlock(BuildContext context, List<(String, String)> rows) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    r.$1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    r.$2,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
