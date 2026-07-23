import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';

import '../../../../core/persistence/test_database.dart';

EventRecord _ev({
  required String id,
  String type = 'trade_closed',
  String source = 'options_trade_journal',
  String ownerUserId = 'u1',
  DateTime? timestamp,
  Set<String> entities = const {'NVDA'},
  double importance = 0.6,
}) => EventRecord(
  id: id,
  type: type,
  timestamp: timestamp ?? DateTime.utc(2026, 5, 20),
  source: source,
  ownerUserId: ownerUserId,
  title: 'NVDA put closed',
  summary: 'cash_secured_put closed.',
  payload: const {'symbol': 'NVDA'},
  entities: entities,
  importance: importance,
);

void main() {
  late SqliteEventStore store;

  setUp(() {
    store = SqliteEventStore(db: makeTestDatabase());
  });

  group('SqliteEventStore', () {
    test('writeEvent + readEvent round-trips', () async {
      await store.writeEvent(_ev(id: 'e1'));
      final back = await store.readEvent('e1');
      expect(back, isNotNull);
      expect(back!.type, 'trade_closed');
      expect(back.entities, {'NVDA'});
      expect(back.payload['symbol'], 'NVDA');
    });

    test('writeEvent is idempotent by id', () async {
      await store.writeEvent(_ev(id: 'e1', importance: 0.5));
      await store.writeEvent(_ev(id: 'e1', importance: 0.9));
      expect(await store.countEvents(), 1);
      final back = await store.readEvent('e1');
      expect(back!.importance, 0.9);
    });

    test('recentEvents returns desc by timestamp', () async {
      await store.writeEvent(
        _ev(id: 'older', timestamp: DateTime.utc(2026, 5, 10)),
      );
      await store.writeEvent(
        _ev(id: 'newer', timestamp: DateTime.utc(2026, 5, 20)),
      );
      final out = await store.recentEvents(ownerUserId: 'u1');
      expect(out.map((e) => e.id), ['newer', 'older']);
    });

    test('recentEvents filters by source', () async {
      await store.writeEvent(_ev(id: 'a', source: 'options_trade_journal'));
      await store.writeEvent(_ev(id: 'b', source: 'health:sleep'));
      final out = await store.recentEvents(
        ownerUserId: 'u1',
        source: 'health:sleep',
      );
      expect(out.map((e) => e.id), ['b']);
    });

    test(
      'recentEvents applies sourcePrefixes as a strict allow-list',
      () async {
        await store.writeEvent(_ev(id: 'finance'));
        await store.writeEvent(_ev(id: 'health', source: 'health:sleep'));
        final out = await store.recentEvents(
          ownerUserId: 'u1',
          sourcePrefixes: const {'health:'},
        );
        expect(out.map((event) => event.id), ['health']);

        final denied = await store.recentEvents(
          ownerUserId: 'u1',
          sourcePrefixes: const <String>{},
        );
        expect(denied, isEmpty);

        final blankDenied = await store.recentEvents(
          ownerUserId: 'u1',
          sourcePrefixes: const <String>{' ', '\t'},
        );
        expect(blankDenied, isEmpty);
      },
    );

    test('sourcePrefixes escapes SQL wildcard characters', () async {
      await store.writeEvent(_ev(id: 'literal', source: r'know_%:notes'));
      await store.writeEvent(_ev(id: 'lookalike', source: 'knowXX:notes'));
      final out = await store.recentEvents(
        ownerUserId: 'u1',
        sourcePrefixes: const {r'know_%:'},
      );
      expect(out.map((event) => event.id), ['literal']);
    });

    test('recentEvents filters by type set', () async {
      await store.writeEvent(_ev(id: 'open', type: 'trade_opened'));
      await store.writeEvent(_ev(id: 'close', type: 'trade_closed'));
      final out = await store.recentEvents(
        ownerUserId: 'u1',
        typeFilter: const {'trade_closed'},
      );
      expect(out.map((e) => e.id), ['close']);
    });

    test('recentEvents filters by entity intersection', () async {
      await store.writeEvent(_ev(id: 'a', entities: const {'NVDA', 'put'}));
      await store.writeEvent(_ev(id: 'b', entities: const {'AAPL', 'call'}));
      final out = await store.recentEvents(
        ownerUserId: 'u1',
        entityFilter: const {'NVDA'},
      );
      expect(out.map((e) => e.id), ['a']);
    });

    test('recentEvents respects time window', () async {
      await store.writeEvent(
        _ev(id: 'old', timestamp: DateTime.utc(2026, 1, 1)),
      );
      await store.writeEvent(
        _ev(id: 'new', timestamp: DateTime.utc(2026, 5, 20)),
      );
      final out = await store.recentEvents(
        ownerUserId: 'u1',
        since: DateTime.utc(2026, 5, 1),
      );
      expect(out.map((e) => e.id), ['new']);
    });

    test('owner isolation', () async {
      await store.writeEvent(_ev(id: 'a', ownerUserId: 'u1'));
      await store.writeEvent(_ev(id: 'b', ownerUserId: 'u2'));
      final out = await store.recentEvents(ownerUserId: 'u1');
      expect(out.single.id, 'a');
    });
  });
}
