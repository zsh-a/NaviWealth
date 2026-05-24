import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';

AiSpan _span({
  String id = 's1',
  String? parentId,
  AiSpanKind kind = AiSpanKind.tool,
  String name = 'tool:get_holdings',
  int start = 100,
  int dur = 50,
  AiSpanStatus status = AiSpanStatus.ok,
  SpanTokens? tokens,
  Object? input,
  Object? output,
}) => AiSpan(
  id: id,
  parentId: parentId,
  kind: kind,
  name: name,
  startOffsetMs: start,
  durationMs: dur,
  status: status,
  tokens: tokens,
  input: input,
  output: output,
  attributes: const {'round': 1},
);

AiTrace _trace({List<AiSpan> spans = const []}) => AiTrace(
  requestId: 'req-1',
  startedAtIso: '2026-05-17T10:00:00.000Z',
  intent: const IntentHint(
    capability: Capability.analyze,
    risk: RiskLevel.suggest,
  ),
  backend: Backend.device,
  budgetTier: BudgetTier.standard,
  routingReason: 'device_llm_direct',
  usedCloud: false,
  totalDurationMs: 1800,
  spans: spans,
);

void main() {
  group('AiSpan', () {
    test('toJson/fromJson round-trips every field', () {
      final s = _span(
        parentId: 'r1',
        tokens: const SpanTokens(input: 10, output: 5, cacheRead: 2),
        input: {'symbol': 'AAPL'},
        output: {'rows': 3},
      );
      final back = AiSpan.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>,
      );
      expect(back.id, 's1');
      expect(back.parentId, 'r1');
      expect(back.kind, AiSpanKind.tool);
      expect(back.startOffsetMs, 100);
      expect(back.endOffsetMs, 150);
      expect(back.tokens!.input, 10);
      expect(back.tokens!.total, 17);
      expect(back.input, {'symbol': 'AAPL'});
      expect(back.output, {'rows': 3});
      expect(back.attributes!['round'], 1);
    });

    test('redacted() drops payloads but keeps metrics', () {
      final r = _span(
        tokens: const SpanTokens(input: 9),
        input: {'big': 'x'},
        output: {'big': 'y'},
      ).redacted();
      expect(r.input, isNull);
      expect(r.output, isNull);
      expect(r.tokens!.input, 9);
      expect(r.durationMs, 50);
      expect(r.attributes!['round'], 1);
    });
  });

  group('AiTrace spans (back-compat + rollups)', () {
    test('legacy JSON without "spans" decodes to empty / hasSpans=false', () {
      final legacy = _trace().toJson()..remove('spans');
      final back = AiTrace.fromJson(legacy);
      expect(back.spans, isEmpty);
      expect(back.hasSpans, isFalse);
    });

    test('omits "spans" key entirely when empty (no blob bloat)', () {
      expect(_trace().toJson().containsKey('spans'), isFalse);
    });

    test('spans survive a full JSON round-trip', () {
      final t = _trace(
        spans: [
          _span(id: 'turn', kind: AiSpanKind.turn, name: 'turn', start: 0),
          _span(id: 'r1', parentId: 'turn', kind: AiSpanKind.llm),
        ],
      );
      final back = AiTrace.fromJson(
        jsonDecode(jsonEncode(t.toJson())) as Map<String, Object?>,
      );
      expect(back.hasSpans, isTrue);
      expect(back.spans.map((s) => s.id), ['turn', 'r1']);
    });

    test('rollups sum LLM tokens and count rounds / errors', () {
      final t = _trace(
        spans: [
          _span(id: 'turn', kind: AiSpanKind.turn, name: 'turn'),
          _span(
            id: 'r1',
            kind: AiSpanKind.llm,
            tokens: const SpanTokens(input: 100, output: 40),
          ),
          _span(
            id: 'r2',
            kind: AiSpanKind.llm,
            tokens: const SpanTokens(input: 200, output: 60, cacheRead: 10),
          ),
          _span(id: 't1', kind: AiSpanKind.tool, status: AiSpanStatus.error),
        ],
      );
      expect(t.llmRoundCount, 2);
      expect(t.toolSpans.length, 1);
      expect(t.errorSpanCount, 1);
      final tot = t.tokenTotals;
      expect(tot.input, 300);
      expect(tot.output, 100);
      expect(tot.cacheRead, 10);
      expect(tot.total, 410);
    });
  });
}
