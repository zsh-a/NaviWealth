import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/trace/ai_trace_builder.dart';

AiTrace _seed() => const AiTrace(
  requestId: 'req-1',
  startedAtIso: '2026-05-17T10:00:00.000Z',
  intent: IntentHint(capability: Capability.analyze, risk: RiskLevel.suggest),
  backend: Backend.device,
  budgetTier: BudgetTier.standard,
  routingReason: 'device_llm_direct',
  totalDurationMs: 0,
);

DateTime _at(int msAfterStart) => DateTime.parse(
  '2026-05-17T10:00:00.000Z',
).add(Duration(milliseconds: msAfterStart));

void main() {
  group('AiTraceBuilder spans', () {
    test('anchors offsets to seed start and synthesises the turn root', () {
      final b = AiTraceBuilder.fromSeed(_seed());
      b.addSpan(
        id: 'r1',
        parentId: kTurnSpanId,
        kind: AiSpanKind.llm,
        name: 'llm:round-1',
        startedAt: _at(200),
        endedAt: _at(900),
        tokens: const SpanTokens(input: 50, output: 12),
      );
      final t = b.finalize(finishedAt: _at(1000));

      expect(t.hasSpans, isTrue);
      final root = t.spans.first;
      expect(root.id, kTurnSpanId);
      expect(root.kind, AiSpanKind.turn);
      expect(root.durationMs, 1000);
      expect(root.status, AiSpanStatus.ok);

      final llm = t.spans[1];
      expect(llm.parentId, kTurnSpanId);
      expect(llm.startOffsetMs, 200);
      expect(llm.durationMs, 700);
      expect(llm.tokens!.input, 50);
    });

    test('metadata-only capture strips input/output, keeps metrics', () {
      final b = AiTraceBuilder.fromSeed(_seed()); // capturePayloads: false
      b.addSpan(
        id: 't1',
        parentId: 'r1',
        kind: AiSpanKind.tool,
        name: 'tool:get_holdings',
        startedAt: _at(300),
        endedAt: _at(360),
        input: {'symbol': 'AAPL'},
        output: {'rows': 5},
      );
      final tool = b.finalize(finishedAt: _at(400)).spans[1];
      expect(tool.input, isNull);
      expect(tool.output, isNull);
      expect(tool.durationMs, 60);
    });

    test('verbose capture preserves input/output', () {
      final b = AiTraceBuilder.fromSeed(_seed(), capturePayloads: true);
      b.addSpan(
        id: 't1',
        kind: AiSpanKind.tool,
        name: 'tool:get_holdings',
        startedAt: _at(300),
        endedAt: _at(360),
        input: {'symbol': 'AAPL'},
        output: {'rows': 5},
      );
      final tool = b.finalize(finishedAt: _at(400)).spans[1];
      expect(tool.input, {'symbol': 'AAPL'});
      expect(tool.output, {'rows': 5});
    });

    test('no spans → empty list (legacy timeline fallback path)', () {
      final t = AiTraceBuilder.fromSeed(_seed()).finalize(finishedAt: _at(500));
      expect(t.spans, isEmpty);
      expect(t.hasSpans, isFalse);
    });

    test('terminal reason maps onto the root span status', () {
      AiTrace run(TerminalReason r) {
        final b = AiTraceBuilder.fromSeed(_seed());
        b.addSpan(
          id: 'r1',
          kind: AiSpanKind.llm,
          name: 'llm:round-1',
          startedAt: _at(10),
          endedAt: _at(20),
        );
        return b.finalize(finishedAt: _at(30), terminalReason: r);
      }

      expect(run(TerminalReason.done).spans.first.status, AiSpanStatus.ok);
      expect(
        run(TerminalReason.userCancel).spans.first.status,
        AiSpanStatus.cancelled,
      );
      expect(
        run(TerminalReason.streamError).spans.first.status,
        AiSpanStatus.error,
      );
    });
  });
}
