import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/trace/trace.dart';

void main() {
  group('InMemoryAiTraceStore', () {
    test('append + recent returns newest first', () async {
      final store = InMemoryAiTraceStore();
      await store.append(_trace('a', '2026-05-10T10:00:00Z'));
      await store.append(_trace('b', '2026-05-10T10:01:00Z'));
      await store.append(_trace('c', '2026-05-10T10:02:00Z'));

      final recent = await store.recent();
      expect(
        recent.map((t) => t.requestId).toList(),
        <String>['c', 'b', 'a'],
      );
    });

    test('recent respects limit', () async {
      final store = InMemoryAiTraceStore();
      for (var i = 0; i < 10; i++) {
        await store.append(_trace('t$i', '2026-05-10T10:0$i:00Z'));
      }
      final recent = await store.recent(limit: 3);
      expect(recent, hasLength(3));
      expect(recent.first.requestId, 't9');
    });

    test('ring-buffers when maxSize exceeded', () async {
      final store = InMemoryAiTraceStore(maxSize: 3);
      for (var i = 0; i < 6; i++) {
        await store.append(_trace('t$i', '2026-05-10T10:0$i:00Z'));
      }
      expect(store.debugLength, 3);
      final recent = await store.recent();
      expect(
        recent.map((t) => t.requestId).toList(),
        <String>['t5', 't4', 't3'],
      );
    });

    test('pruneOlderThan drops only entries strictly older than cutoff', () async {
      final store = InMemoryAiTraceStore();
      await store.append(_trace('old', '2026-04-01T00:00:00Z'));
      await store.append(_trace('mid', '2026-05-01T00:00:00Z'));
      await store.append(_trace('new', '2026-05-09T00:00:00Z'));

      await store.pruneOlderThan(DateTime.utc(2026, 5, 1));
      final recent = await store.recent();
      expect(
        recent.map((t) => t.requestId).toSet(),
        <String>{'mid', 'new'},
      );
    });

    test('recent on empty store is empty list, not null', () async {
      final store = InMemoryAiTraceStore();
      expect(await store.recent(), isEmpty);
    });
  });

  group('AiTraceBuilder', () {
    test('finalize captures spans + disclosures and computes duration', () {
      const seed = AiTrace(
        requestId: 'req-1',
        startedAtIso: '2026-05-10T10:00:00.000Z',
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.suggest,
        ),
        backend: Backend.hybrid,
        budgetTier: BudgetTier.standard,
        routingReason: 'analyze_hybrid',
        usedCloud: true,
        usedRawLedger: false,
        totalDurationMs: 0,
      );
      final start = DateTime.parse('2026-05-10T10:00:00.000Z');
      final builder = AiTraceBuilder.fromSeed(seed)
        ..addSpan(
          id: 'r1',
          parentId: kTurnSpanId,
          kind: AiSpanKind.llm,
          name: 'llm:round-1',
          startedAt: start.add(const Duration(milliseconds: 10)),
          endedAt: start.add(const Duration(milliseconds: 60)),
          tokens: const SpanTokens(input: 30, output: 9),
        )
        ..addDisclosure(
          const DisclosureSummary(
            purpose: DisclosurePurpose.anomalyExplain,
            fieldsCount: 3,
            rowCount: 12,
            consent: UserConsent.session,
          ),
        )
        ..addSpan(
          id: 'tool:t1',
          parentId: 'r1',
          kind: AiSpanKind.tool,
          name: 'tool:request_disclosure',
          startedAt: start.add(const Duration(milliseconds: 20)),
          endedAt: start.add(const Duration(milliseconds: 220)),
        );

      final trace = builder.finalize(
        finishedAt: DateTime.utc(2026, 5, 10, 10, 0, 3),
      );

      expect(trace.totalDurationMs, 3000);
      // turn root + llm + tool.
      expect(trace.spans, hasLength(3));
      expect(trace.llmRoundCount, 1);
      expect(trace.toolSpans.single.name, 'tool:request_disclosure');
      expect(trace.disclosures, hasLength(1));
      // Consented disclosure flips the privacy badge.
      expect(trace.usedRawLedger, isTrue);
    });

    test('denied-only disclosures keep usedRawLedger false', () {
      const seed = AiTrace(
        requestId: 'req-1',
        startedAtIso: '2026-05-10T10:00:00.000Z',
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
        backend: Backend.hybrid,
        budgetTier: BudgetTier.standard,
        routingReason: 'analyze_hybrid',
        usedCloud: true,
        usedRawLedger: false,
        totalDurationMs: 0,
      );
      final builder = AiTraceBuilder.fromSeed(seed)
        ..addDisclosure(
          const DisclosureSummary(
            purpose: DisclosurePurpose.drillDownExpense,
            fieldsCount: 0,
            rowCount: 0,
            consent: UserConsent.denied,
          ),
        );
      final trace = builder.finalize(
        finishedAt: DateTime.utc(2026, 5, 10, 10, 0, 1),
      );
      expect(trace.usedRawLedger, isFalse);
    });

    test('clamps negative duration to zero', () {
      const seed = AiTrace(
        requestId: 'req-1',
        startedAtIso: '2026-05-10T10:00:05.000Z',
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
        backend: Backend.device,
        budgetTier: BudgetTier.small,
        routingReason: 'analyze_offline_template',
        usedCloud: false,
        usedRawLedger: false,
        totalDurationMs: 0,
      );
      final trace = AiTraceBuilder.fromSeed(seed).finalize(
        // earlier than seed.startedAt — clock skew between caller layers
        finishedAt: DateTime.utc(2026, 5, 10, 10, 0, 0),
      );
      expect(trace.totalDurationMs, 0);
    });
  });
}

AiTrace _trace(String id, String iso) => AiTrace(
  requestId: id,
  startedAtIso: iso,
  intent: const IntentHint(
    capability: Capability.analyze,
    risk: RiskLevel.info,
  ),
  backend: Backend.device,
  budgetTier: BudgetTier.small,
  routingReason: 'test',
  usedCloud: false,
  usedRawLedger: false,
  totalDurationMs: 0,
);
