import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/options_income/data/trade_journal_memory_indexer.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';

import '../../../../core/persistence/test_database.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u1',
  updatedAt: DateTime.utc(2026, 5, 24),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
);

TradeJournalEntry _entry({
  String id = 'e',
  String symbol = 'NVDA',
  String currency = 'USD',
  OptionsStrategyKind strategy = OptionsStrategyKind.cashSecuredPut,
  TradeJournalStatus status = TradeJournalStatus.open,
  DateTime? openedAt,
  DateTime? closedAt,
  String entryCredit = '1.25',
  String? realizedPnl,
  String? notes,
}) => TradeJournalEntry(
  underlyingAssetId: 'nasdaq:AAPL',
  id: id,
  strategy: strategy,
  symbol: symbol,
  optionSymbol: '$symbol-OPT',
  openedAt: openedAt ?? DateTime.utc(2026, 5, 1),
  closedAt: closedAt,
  entryCredit: Decimal.parse(entryCredit),
  exitDebit: null,
  realizedPnl: realizedPnl == null ? null : Decimal.parse(realizedPnl),
  currency: currency,
  status: status,
  notes: notes,
  sync: _meta(),
);

MemoryRuntime _runtime() {
  final db = makeTestDatabase();
  return MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
}

void main() {
  group('TradeJournalMemoryIndexer.reindex — event emission', () {
    test('open status emits trade_opened event, no episodic memory', () async {
      final rt = _runtime();
      final indexer = TradeJournalMemoryIndexer();
      final out = await indexer.reindex(rt, [
        _entry(id: 'open-1', status: TradeJournalStatus.open),
      ], ownerUserId: 'u1');
      expect(out.events, 1);
      expect(out.memories, 0);

      final events = await rt.recentEvents(
        ownerUserId: 'u1',
        window: const Duration(days: 9999),
      );
      expect(events.single.type, kEventTradeOpened);
      expect(events.single.entities, containsAll(['NVDA']));
    });

    test('closed status emits trade_closed event + episodic memory', () async {
      final rt = _runtime();
      final indexer = TradeJournalMemoryIndexer();
      final out = await indexer.reindex(rt, [
        _entry(
          id: 'closed-1',
          status: TradeJournalStatus.closed,
          closedAt: DateTime.utc(2026, 5, 20),
          realizedPnl: '0.65',
          notes: '提前平仓; IV 已回落',
        ),
      ], ownerUserId: 'u1');
      expect(out.events, 1);
      expect(out.memories, 1);

      final hits = await rt.recall(
        ownerUserId: 'u1',
        queryText: 'NVDA put closed',
        kinds: const {MemoryKind.episodic},
      );
      expect(hits, hasLength(1));
      final rec = hits.single.record;
      expect(rec.kind, MemoryKind.episodic);
      expect(rec.scope, 'options_trading');
      expect(rec.sourceEventId, isNotNull);
      expect(rec.payload['reasoning'], '提前平仓; IV 已回落');
      expect((rec.payload['outcome']! as Map)['status'], 'closed');
    });

    test('assigned status has higher importance than expired', () async {
      final rt = _runtime();
      final indexer = TradeJournalMemoryIndexer();
      await indexer.reindex(rt, [
        _entry(
          id: 'assigned',
          status: TradeJournalStatus.assigned,
          closedAt: DateTime.utc(2026, 5, 20),
        ),
        _entry(
          id: 'expired',
          status: TradeJournalStatus.expired,
          closedAt: DateTime.utc(2026, 5, 20),
        ),
      ], ownerUserId: 'u1');

      final all = await rt.recall(
        ownerUserId: 'u1',
        kinds: const {MemoryKind.episodic},
        topK: 5,
      );
      final assigned = all.firstWhere((h) => h.record.id.contains('assigned'));
      final expired = all.firstWhere((h) => h.record.id.contains('expired'));
      expect(
        assigned.record.importance,
        greaterThan(expired.record.importance),
      );
    });

    test('notes attached lifts importance (vs same-status no-notes)', () async {
      final rt = _runtime();
      final indexer = TradeJournalMemoryIndexer();
      await indexer.reindex(rt, [
        _entry(
          id: 'with-notes',
          status: TradeJournalStatus.closed,
          closedAt: DateTime.utc(2026, 5, 20),
          notes: 'remembered why',
        ),
        _entry(
          id: 'no-notes',
          status: TradeJournalStatus.closed,
          closedAt: DateTime.utc(2026, 5, 20),
        ),
      ], ownerUserId: 'u1');
      final hits = await rt.recall(
        ownerUserId: 'u1',
        kinds: const {MemoryKind.episodic},
        topK: 5,
      );
      final withNotes = hits
          .firstWhere((h) => h.record.id.contains('with-notes'))
          .record
          .importance;
      final without = hits
          .firstWhere((h) => h.record.id.contains('no-notes'))
          .record
          .importance;
      expect(withNotes, greaterThan(without));
    });

    test('reindex is idempotent — same ids, no duplicates', () async {
      final rt = _runtime();
      final indexer = TradeJournalMemoryIndexer();
      final entry = _entry(
        id: 'idem',
        status: TradeJournalStatus.closed,
        closedAt: DateTime.utc(2026, 5, 20),
        notes: 'v1',
      );
      await indexer.reindex(rt, [entry], ownerUserId: 'u1');
      await indexer.reindex(rt, [
        entry.copyWith(notes: 'v2'),
      ], ownerUserId: 'u1');
      expect(await rt.eventCount, 1);
      expect(await rt.memoryCount, 1);
      final hit = (await rt.recall(
        ownerUserId: 'u1',
        kinds: const {MemoryKind.episodic},
      )).single.record;
      expect(hit.payload['reasoning'], 'v2');
    });

    test('owner isolation — entries scoped per user', () async {
      final rt = _runtime();
      final indexer = TradeJournalMemoryIndexer();
      await indexer.reindex(rt, [
        _entry(
          id: 'a',
          status: TradeJournalStatus.closed,
          closedAt: DateTime.utc(2026, 5, 20),
        ),
      ], ownerUserId: 'u1');
      await indexer.reindex(rt, [
        _entry(
          id: 'b',
          status: TradeJournalStatus.closed,
          closedAt: DateTime.utc(2026, 5, 20),
        ),
      ], ownerUserId: 'u2');
      final u1 = await rt.recall(ownerUserId: 'u1', queryText: 'NVDA');
      final u2 = await rt.recall(ownerUserId: 'u2', queryText: 'NVDA');
      expect(u1, hasLength(1));
      expect(u2, hasLength(1));
    });

    test('events carry stable type-prefixed ids for back-pointers', () async {
      final rt = _runtime();
      final indexer = TradeJournalMemoryIndexer();
      await indexer.reindex(rt, [
        _entry(
          id: 'X',
          status: TradeJournalStatus.assigned,
          closedAt: DateTime.utc(2026, 5, 20),
        ),
      ], ownerUserId: 'u1');
      final hits = await rt.recall(
        ownerUserId: 'u1',
        kinds: const {MemoryKind.episodic},
      );
      final memory = hits.single.record;
      expect(memory.sourceEventId, 'options_trade_journal:trade_assigned:X');
      final event = await rt.eventStore.readEvent(memory.sourceEventId!);
      expect(event, isNotNull);
      expect(event!.type, kEventTradeAssigned);
    });

    test('empty input is a no-op', () async {
      final rt = _runtime();
      final indexer = TradeJournalMemoryIndexer();
      final out = await indexer.reindex(rt, const [], ownerUserId: 'u1');
      expect(out.events, 0);
      expect(out.memories, 0);
    });
  });
}
