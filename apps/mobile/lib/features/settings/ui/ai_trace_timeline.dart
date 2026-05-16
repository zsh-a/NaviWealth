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

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/visual/visual.dart';

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
  /// [AiTone.error]; normal events fall through to [AiTone.outline] so
  /// the timeline stays muted.
  Color tone(BuildContext context);

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
  IconData get icon => FIcons.flag;

  // Wave 36: AI surfaces commit to a single accent — invocation rail
  // uses `active`, every other "informational" event uses outline tone.
  @override
  Color tone(BuildContext context) => AiTone.active(context);

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
  IconData get icon => FIcons.route;

  // Wave 36 — routing is informational, not "alive": muted tone keeps
  // it out of visual competition with the active invocation marker.
  @override
  Color tone(BuildContext context) => AiTone.outline(context);

  @override
  Widget? expandedBody(BuildContext context) =>
      _kvBlock(context, <(String, String)>[
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
  IconData get icon => ok ? FIcons.bolt : FIcons.circleAlert;

  @override
  Color tone(BuildContext context) =>
      ok ? AiTone.muted(context) : AiTone.error(context);
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
  IconData get icon => FIcons.lock;

  // Wave 36 — color discipline: disclosures don't get their own hue.
  // Denied → muted (this didn't actually happen), accepted → active
  // (signal that real data was shared).
  @override
  Color tone(BuildContext context) =>
      consent == 'denied' ? AiTone.outline(context) : AiTone.active(context);
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
  IconData get icon => FIcons.refreshCw;

  // Wave 36 — staleness is encoded by the `update_outlined` icon, not
  // by color. Tone is muted; the icon does the signaling.
  @override
  Color tone(BuildContext context) => AiTone.outline(context);

  @override
  Widget? expandedBody(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [for (final name in readModelNames) AiPill(label: name)],
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
  IconData get icon => reason == 'done' ? FIcons.circleCheck : FIcons.circleX;

  @override
  Color tone(BuildContext context) =>
      reason == 'done' ? AiTone.active(context) : AiTone.error(context);
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
      FreshnessAlertEvent(readModelNames: trace.staleReadModelNames.toList()),
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
    final available = <TraceEventKind>{for (final e in widget.events) e.kind};
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
              style: AiType.body(
                context,
              ).copyWith(color: AiTone.muted(context)),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final k in TraceEventKind.values)
            if (available.contains(k))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: AiPill(
                  label: _labelFor(k),
                  state: active.contains(k)
                      ? AiPillState.selected
                      : AiPillState.neutral,
                  onTap: () => onToggle(k),
                ),
              ),
        ],
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
    final outline = AiTone.outline(context);
    final tone = event.tone(context);
    final row = IntrinsicHeight(
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
                      : ColoredBox(color: outline.withValues(alpha: 0.7)),
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
                        : ColoredBox(color: outline.withValues(alpha: 0.7)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // ── Right: event card ─────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8, right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: AiType.body(
                            context,
                          ).copyWith(fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onTap != null)
                        Icon(
                          expanded ? FIcons.chevronUp : FIcons.chevronDown,
                          size: 16,
                          color: AiTone.muted(context),
                        ),
                    ],
                  ),
                  if (event.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      event.subtitle,
                      style: AiType.meta(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (expanded) ...[
                    const SizedBox(height: 6),
                    AnimatedSize(
                      duration: AiMotion.short,
                      curve: AiMotion.standard,
                      child:
                          event.expandedBody(context) ??
                          const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return FTappable(onPress: onTap, child: row);
  }
}

Widget _kvBlock(BuildContext context, List<(String, String)> rows) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AiTone.surfaceTint(context).withValues(alpha: 0.4),
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
                  child: Text(r.$1, style: AiType.meta(context)),
                ),
                Expanded(
                  child: Text(
                    r.$2,
                    style: AiType.body(
                      context,
                    ).copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
