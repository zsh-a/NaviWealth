// Timeline builder contract — turns AiTrace data into ordered events.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/features/settings/ui/ai_trace_timeline.dart';

void main() {
  AiTrace minimal({
    Map<String, Object?>? invocation,
    List<TraceToolCall> tools = const <TraceToolCall>[],
    List<DisclosureSummary> disclosures = const <DisclosureSummary>[],
    Set<String> stale = const <String>{},
    TerminalReason terminal = TerminalReason.done,
  }) => AiTrace(
    requestId: 'r',
    startedAtIso: '2026-05-12T00:00:00Z',
    intent: const IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.suggest,
      label: 'turn',
    ),
    backend: Backend.cloud,
    budgetTier: BudgetTier.small,
    routingReason: 'capability_analyze_online',
    usedCloud: true,
    usedRawLedger: false,
    totalDurationMs: 500,
    toolCalls: tools,
    disclosures: disclosures,
    staleReadModelNames: stale,
    terminalReason: terminal,
    invocation: invocation,
  );

  test('minimal trace yields RoutingEvent + TerminalEvent', () {
    final events = buildTimeline(minimal());
    expect(events, hasLength(2));
    expect(events[0], isA<RoutingEvent>());
    expect(events[1], isA<TerminalEvent>());
  });

  test('invocation present: InvocationEvent leads the timeline', () {
    final events = buildTimeline(minimal(invocation: <String, Object?>{
      'source': 'expense_detail',
      'intent': 'explain_change',
      'object_type': 'expense',
      'object_id': 'exp_1',
      'context_keys': <String>['timeframe'],
    }));
    expect(events.first, isA<InvocationEvent>());
    final inv = events.first as InvocationEvent;
    expect(inv.source, 'expense_detail');
    expect(inv.intent, 'explain_change');
    expect(inv.contextKeys, <String>['timeframe']);
  });

  test('tool calls preserve emission order with 1/N index labels', () {
    final events = buildTimeline(minimal(tools: const [
      TraceToolCall(name: 'get_holdings', durationMs: 30, ok: true),
      TraceToolCall(name: 'compute_xirr', durationMs: 80, ok: true),
      TraceToolCall(name: 'get_subscription_changes', durationMs: 12, ok: false),
    ]));
    final toolEvents = events.whereType<ToolCallEvent>().toList();
    expect(toolEvents, hasLength(3));
    expect(toolEvents[0].indexLabel, '1/3');
    expect(toolEvents[0].name, 'get_holdings');
    expect(toolEvents[1].indexLabel, '2/3');
    expect(toolEvents[2].indexLabel, '3/3');
    expect(toolEvents[2].ok, isFalse);
  });

  test('error tool calls flagged for error-toned rail', () {
    final events = buildTimeline(minimal(tools: const [
      TraceToolCall(name: 'broken_tool', durationMs: 5, ok: false),
    ]));
    final tool = events.whereType<ToolCallEvent>().single;
    expect(tool.ok, isFalse);
  });

  test('freshness alert appears only when stale set non-empty', () {
    expect(
      buildTimeline(minimal()).whereType<FreshnessAlertEvent>(),
      isEmpty,
    );
    final withStale = buildTimeline(minimal(stale: {
      'holdings_snapshot',
      'net_worth_snapshot',
    }));
    final alert = withStale.whereType<FreshnessAlertEvent>().single;
    expect(alert.readModelNames.length, 2);
  });

  test('disclosures inject DisclosureEvent rows', () {
    final events = buildTimeline(minimal(disclosures: const [
      DisclosureSummary(
        purpose: DisclosurePurpose.anomalyExplain,
        fieldsCount: 4,
        rowCount: 12,
        consent: UserConsent.session,
      ),
    ]));
    final d = events.whereType<DisclosureEvent>().single;
    expect(d.rowCount, 12);
    expect(d.consent, 'session');
  });

  test('TerminalEvent reflects terminalReason; error reason switches tone marker',
      () {
    final ok = buildTimeline(minimal()).last as TerminalEvent;
    expect(ok.reason, 'done');
    final err = buildTimeline(minimal(terminal: TerminalReason.streamError))
        .last as TerminalEvent;
    expect(err.reason, 'stream_error');
  });

  test('full-shape trace order: invocation → routing → tools → disclosures → freshness → terminal',
      () {
    final events = buildTimeline(minimal(
      invocation: <String, Object?>{
        'source': 'home_insight',
        'intent': 'explain_insight',
      },
      tools: const [
        TraceToolCall(name: 'get_anomaly_flags', durationMs: 22, ok: true),
        TraceToolCall(name: 'get_recurring_patterns', durationMs: 15, ok: true),
      ],
      disclosures: const [
        DisclosureSummary(
          purpose: DisclosurePurpose.anomalyExplain,
          fieldsCount: 3,
          rowCount: 5,
          consent: UserConsent.denied,
        ),
      ],
      stale: {'anomaly_flags'},
      terminal: TerminalReason.userCancel,
    ));
    expect(events.map((e) => e.kind).toList(), <TraceEventKind>[
      TraceEventKind.invocation,
      TraceEventKind.routing,
      TraceEventKind.toolCall,
      TraceEventKind.toolCall,
      TraceEventKind.disclosure,
      TraceEventKind.freshnessAlert,
      TraceEventKind.terminal,
    ]);
  });
}
