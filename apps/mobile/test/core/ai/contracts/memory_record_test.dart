import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';

void main() {
  group('MemoryKindWire', () {
    test('all four kinds round-trip through wire', () {
      for (final k in MemoryKind.values) {
        expect(MemoryKindWire.parse(k.wire), k);
      }
    });

    test('unknown wire defaults to event', () {
      expect(MemoryKindWire.parse('bogus'), MemoryKind.event);
    });
  });

  group('MemoryRecord JSON round-trip', () {
    test('episodic record preserves all fields', () {
      final now = DateTime.utc(2026, 5, 24, 10);
      final original = MemoryRecord(
        id: 'mem-1',
        kind: MemoryKind.episodic,
        ownerUserId: 'u1',
        scope: 'options_trading',
        source: 'options_trade_journal',
        sourceId: 'trade-42',
        sourceEventId: 'options_trade_journal:trade_closed:trade-42',
        title: 'NVDA put closed',
        summary: 'Closed early at 70% credit, IV had collapsed.',
        payload: const {
          'context': 'opened 2026-05-01',
          'decision': 'sell put',
          'reasoning': 'long-term bullish',
          'outcome': {'status': 'closed', 'realized_pnl': '0.65'},
        },
        entities: const {'NVDA', 'put'},
        importance: 0.7,
        confidence: 0.9,
        validFrom: DateTime.utc(2026, 5, 1),
        createdAt: now,
        updatedAt: now,
      );
      final back = MemoryRecord.fromJson(original.toJson());
      expect(back.id, 'mem-1');
      expect(back.kind, MemoryKind.episodic);
      expect(back.scope, 'options_trading');
      expect(back.source, 'options_trade_journal');
      expect(back.sourceId, 'trade-42');
      expect(back.sourceEventId, isNotNull);
      expect(back.title, 'NVDA put closed');
      expect(back.payload['reasoning'], 'long-term bullish');
      expect(back.entities, {'NVDA', 'put'});
      expect(back.importance, 0.7);
      expect(back.confidence, 0.9);
      expect(back.validFrom, DateTime.utc(2026, 5, 1));
      expect(back.updatedAt, now);
    });

    test('nullable optionals stay null after round-trip', () {
      final now = DateTime.utc(2026, 5, 24);
      final r = MemoryRecord(
        id: 'mem-2',
        kind: MemoryKind.semantic,
        ownerUserId: 'u1',
        title: 'user prefers local-first',
        summary: 'observed across sessions',
        payload: const {'statement': 'user prefers local-first'},
        entities: const {},
        importance: 0.9,
        confidence: 0.95,
        createdAt: now,
        updatedAt: now,
      );
      final back = MemoryRecord.fromJson(r.toJson());
      expect(back.source, isNull);
      expect(back.sourceId, isNull);
      expect(back.sourceEventId, isNull);
      expect(back.validFrom, isNull);
      expect(back.validUntil, isNull);
      expect(back.lastAccessedAt, isNull);
      expect(back.scope, '*');
    });

    test('encodePayload + decodePayload roundtrip nested maps', () {
      const payload = <String, Object?>{
        'a': 1,
        'b': {
          'c': 'two',
          'd': [3, 4],
        },
      };
      final encoded = MemoryRecord(
        id: 'x',
        kind: MemoryKind.event,
        ownerUserId: 'u',
        title: 't',
        summary: 's',
        payload: payload,
        entities: const {},
        importance: 0.5,
        confidence: 0.8,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ).encodePayload();
      final back = MemoryRecord.decodePayload(encoded);
      expect(back['a'], 1);
      expect((back['b']! as Map)['c'], 'two');
    });

    test('encodeEntities + decodeEntities preserve set semantics', () {
      final e = MemoryRecord(
        id: 'x',
        kind: MemoryKind.event,
        ownerUserId: 'u',
        title: 't',
        summary: 's',
        payload: const {},
        entities: const {'NVDA', 'put', 'cash_secured_put'},
        importance: 0.5,
        confidence: 0.8,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final back = MemoryRecord.decodeEntities(e.encodeEntities());
      expect(back, {'NVDA', 'put', 'cash_secured_put'});
    });
  });

  group('EventRecord JSON round-trip', () {
    test('preserves all fields', () {
      final ts = DateTime.utc(2026, 5, 24, 9);
      final original = EventRecord(
        id: 'evt-1',
        type: 'trade_closed',
        timestamp: ts,
        source: 'options_trade_journal',
        ownerUserId: 'u1',
        title: 'NVDA put closed',
        summary: 'cash_secured_put closed.',
        payload: const {'symbol': 'NVDA', 'realized_pnl': '0.65'},
        entities: const {'NVDA', 'cash_secured_put'},
        importance: 0.6,
      );
      final back = EventRecord.fromJson(original.toJson());
      expect(back.id, 'evt-1');
      expect(back.type, 'trade_closed');
      expect(back.timestamp, ts);
      expect(back.payload['symbol'], 'NVDA');
      expect(back.entities, {'NVDA', 'cash_secured_put'});
      expect(back.importance, 0.6);
    });
  });
}
