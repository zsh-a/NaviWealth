// Wave 23 — DriftAiTraceStore contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/trace/drift_ai_trace_store.dart';

import '../../../data/db/test_database.dart';

void main() {
  AiTrace trace({required String id, required DateTime startedAt}) => AiTrace(
    requestId: id,
    startedAtIso: startedAt.toUtc().toIso8601String(),
    intent: const IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.suggest,
      label: 'chat_turn',
    ),
    backend: Backend.cloud,
    budgetTier: BudgetTier.small,
    routingReason: 'test',
    totalDurationMs: 12,
  );

  test('append + recent round-trips', () async {
    final db = makeTestDatabase();
    final store = DriftAiTraceStore(db);

    await store.append(trace(id: 'r1', startedAt: DateTime.utc(2026, 5, 12, 9)));
    await store.append(trace(id: 'r2', startedAt: DateTime.utc(2026, 5, 12, 10)));
    await store.append(trace(id: 'r3', startedAt: DateTime.utc(2026, 5, 12, 11)));

    final recent = await store.recent();
    expect(recent, hasLength(3));
    // Newest first.
    expect(recent.map((t) => t.requestId), <String>['r3', 'r2', 'r1']);
    expect(recent.first.intent.label, 'chat_turn');

    await db.close();
  });

  test('findByRequestId returns the matching trace', () async {
    final db = makeTestDatabase();
    final store = DriftAiTraceStore(db);
    await store.append(trace(id: 'r1', startedAt: DateTime.utc(2026, 5, 12)));
    final hit = await store.findByRequestId('r1');
    expect(hit, isNotNull);
    expect(hit!.requestId, 'r1');
    final miss = await store.findByRequestId('nope');
    expect(miss, isNull);
    await db.close();
  });

  test('pruneOlderThan deletes strictly older rows', () async {
    final db = makeTestDatabase();
    final store = DriftAiTraceStore(db);
    await store.append(trace(id: 'old', startedAt: DateTime.utc(2026, 1, 1)));
    await store.append(trace(id: 'mid', startedAt: DateTime.utc(2026, 4, 1)));
    await store.append(trace(id: 'new', startedAt: DateTime.utc(2026, 5, 1)));

    await store.pruneOlderThan(DateTime.utc(2026, 3, 1));
    final after = await store.recent();
    expect(after.map((t) => t.requestId), <String>['new', 'mid']);

    await db.close();
  });

  test('owner partition scopes reads', () async {
    final db = makeTestDatabase();
    final alice = DriftAiTraceStore(db, ownerUserId: 'alice');
    final bob = DriftAiTraceStore(db, ownerUserId: 'bob');

    await alice.append(trace(id: 'a1', startedAt: DateTime.utc(2026, 5, 12)));
    await bob.append(trace(id: 'b1', startedAt: DateTime.utc(2026, 5, 12)));

    expect((await alice.recent()).map((t) => t.requestId), <String>['a1']);
    expect((await bob.recent()).map((t) => t.requestId), <String>['b1']);

    await db.close();
  });

  test('append upserts on duplicate request_id', () async {
    final db = makeTestDatabase();
    final store = DriftAiTraceStore(db);
    await store.append(trace(id: 'r1', startedAt: DateTime.utc(2026, 5, 12, 9)));
    await store.append(trace(id: 'r1', startedAt: DateTime.utc(2026, 5, 12, 10)));
    final all = await store.recent();
    expect(all, hasLength(1));
    expect(all.single.requestId, 'r1');
    expect(all.single.startedAtIso, '2026-05-12T10:00:00.000Z');
    await db.close();
  });
}
