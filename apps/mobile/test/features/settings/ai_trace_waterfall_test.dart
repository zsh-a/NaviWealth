import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/features/settings/ui/ai_trace_waterfall.dart';

AiTrace _trace() => const AiTrace(
  requestId: 'req-1',
  startedAtIso: '2026-05-17T10:00:00.000Z',
  intent: IntentHint(
    capability: Capability.analyze,
    risk: RiskLevel.suggest,
  ),
  backend: Backend.device,
  budgetTier: BudgetTier.standard,
  routingReason: 'device_llm_direct',
  usedCloud: false,
  usedRawLedger: false,
  totalDurationMs: 1500,
  spans: [
    AiSpan(
      id: 'turn',
      kind: AiSpanKind.turn,
      name: 'turn',
      startOffsetMs: 0,
      durationMs: 1500,
    ),
    AiSpan(
      id: 'r1',
      parentId: 'turn',
      kind: AiSpanKind.llm,
      name: 'llm:round-1',
      startOffsetMs: 0,
      durationMs: 600,
      model: 'claude-sonnet-4-6',
      stopReason: 'tool_use',
      tokens: SpanTokens(input: 1000, output: 200),
    ),
    AiSpan(
      id: 'tool:t1',
      parentId: 'r1',
      kind: AiSpanKind.tool,
      name: 'tool:get_holdings',
      startOffsetMs: 120,
      durationMs: 180,
      input: {'unit': 'USD'},
      output: {'rows': 3},
    ),
  ],
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('buildSpanTree', () {
    test('roots at turn, depth-first, ordered by start', () {
      final rows = buildSpanTree(_trace().spans);
      expect(rows.map((r) => r.span.id), ['turn', 'r1', 'tool:t1']);
      expect(rows.map((r) => r.depth), [0, 1, 2]);
    });

    test('dangling parent is promoted to a root (nothing dropped)', () {
      final rows = buildSpanTree(const [
        AiSpan(
          id: 'x',
          parentId: 'missing',
          kind: AiSpanKind.tool,
          name: 'tool:x',
          startOffsetMs: 0,
          durationMs: 1,
        ),
      ]);
      expect(rows.single.span.id, 'x');
      expect(rows.single.depth, 0);
    });
  });

  group('AiTraceWaterfall widget', () {
    testWidgets('renders the rollup + span rows, drills into detail', (
      tester,
    ) async {
      await _pump(tester, AiTraceWaterfall(trace: _trace()));

      // Rollup strip.
      expect(find.text('1 rounds'), findsOneWidget);
      expect(find.text('1 tools'), findsOneWidget);
      // Span labels (short form).
      expect(find.text('get_holdings'), findsOneWidget);

      // Tap the tool row → detail panel appears with metadata + IO.
      await tester.tap(find.text('get_holdings'));
      await tester.pumpAndSettle();
      expect(find.text('tool:get_holdings'), findsOneWidget);
      expect(find.textContaining('window'), findsOneWidget);
      expect(find.text('input'), findsOneWidget);
      expect(find.text('output'), findsOneWidget);
    });

    testWidgets('cost estimate resolves for a known model', (tester) async {
      final c = estimateTraceCostCny(_trace());
      expect(c, isNotNull);
      expect(c, greaterThan(0));
    });
  });
}
