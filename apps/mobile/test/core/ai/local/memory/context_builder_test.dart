import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/context_pack_memory.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/context_builder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';

import '../../../../core/persistence/test_database.dart';

const _kOwner = 'u1';
final _fixtureNow = DateTime.utc(2026, 5, 24);

MemoryRecord _mem({
  required String id,
  required MemoryKind kind,
  String scope = 'options_trading',
  String title = '',
  String summary = '',
  Set<String> entities = const {},
  double importance = 0.6,
  double confidence = 0.85,
}) => MemoryRecord(
  id: id,
  kind: kind,
  ownerUserId: _kOwner,
  scope: scope,
  source: 'test',
  title: title.isEmpty ? id : title,
  summary: summary.isEmpty ? 'summary $id' : summary,
  payload: const {},
  entities: entities,
  importance: importance,
  confidence: confidence,
  createdAt: DateTime.utc(2026, 5, 24),
  updatedAt: DateTime.utc(2026, 5, 24),
);

ContextBuilder _builder({DateTime Function()? clock}) {
  final db = makeTestDatabase();
  final runtime = MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
    clock: clock ?? () => _fixtureNow,
  );
  return ContextBuilder(runtime: runtime);
}

void main() {
  group('ContextBuilder.build', () {
    test('empty runtime returns empty pack with isEmpty flag', () async {
      final b = _builder();
      final pack = await b.build(
        ownerUserId: _kOwner,
        intent: const ContextIntent(),
      );
      expect(pack.isEmpty, isTrue);
      expect(pack.userPreferences, isEmpty);
      expect(pack.recentEvents, isEmpty);
    });

    test('classifies records into correct slots', () async {
      final b = _builder();
      final r = b.runtime;
      await r.remember(_mem(id: 'pref', kind: MemoryKind.semantic, scope: '*'));
      await r.remember(_mem(id: 'rule', kind: MemoryKind.procedural));
      await r.remember(
        _mem(
          id: 'decision',
          kind: MemoryKind.episodic,
          summary: 'NVDA put closed',
        ),
      );
      await r.recordEvent(
        EventRecord(
          id: 'event-1',
          type: 'trade_closed',
          timestamp: DateTime.utc(2026, 5, 23),
          source: 'options_trade_journal',
          ownerUserId: _kOwner,
          summary: 'closed something',
          payload: const {},
          entities: const {'NVDA'},
        ),
      );

      final pack = await b.build(
        ownerUserId: _kOwner,
        intent: const ContextIntent(
          freeText: 'NVDA put',
          scope: 'options_trading',
        ),
      );
      expect(pack.userPreferences.map((m) => m.id), ['pref']);
      expect(pack.applicableRules.map((m) => m.id), ['rule']);
      expect(pack.relatedDecisions.map((m) => m.id), ['decision']);
      expect(pack.recentEvents.map((e) => e.id), ['event-1']);
    });

    test('scope filter only affects scoped slots, not events', () async {
      final b = _builder();
      final r = b.runtime;
      await r.remember(
        _mem(
          id: 'in-scope',
          kind: MemoryKind.procedural,
          scope: 'options_trading',
        ),
      );
      await r.remember(
        _mem(id: 'out-of-scope', kind: MemoryKind.procedural, scope: 'fire'),
      );
      await r.recordEvent(
        EventRecord(
          id: 'event-1',
          type: 'whatever',
          timestamp: DateTime.utc(2026, 5, 23),
          source: 'x',
          ownerUserId: _kOwner,
          summary: 's',
          payload: const {},
          entities: const {},
        ),
      );

      final pack = await b.build(
        ownerUserId: _kOwner,
        intent: const ContextIntent(scope: 'options_trading'),
      );
      expect(pack.applicableRules.map((m) => m.id), ['in-scope']);
      expect(pack.recentEvents, hasLength(1));
    });

    test(
      'related_events is the entity-filtered subset of recent_events',
      () async {
        final b = _builder();
        final r = b.runtime;
        final ts = DateTime.utc(2026, 5, 23);
        await r.recordEvent(
          EventRecord(
            id: 'nvda',
            type: 't',
            timestamp: ts,
            source: 'x',
            ownerUserId: _kOwner,
            summary: 's',
            payload: const {},
            entities: const {'NVDA'},
          ),
        );
        await r.recordEvent(
          EventRecord(
            id: 'aapl',
            type: 't',
            timestamp: ts.add(const Duration(hours: 1)),
            source: 'x',
            ownerUserId: _kOwner,
            summary: 's',
            payload: const {},
            entities: const {'AAPL'},
          ),
        );

        final pack = await b.build(
          ownerUserId: _kOwner,
          intent: const ContextIntent(entities: {'NVDA'}),
        );
        expect(
          pack.recentEvents.map((e) => e.id),
          containsAll(['nvda', 'aapl']),
        );
        expect(pack.relatedEvents.map((e) => e.id), ['nvda']);
      },
    );

    test('kindHints restricts which slots are populated', () async {
      final b = _builder();
      final r = b.runtime;
      await r.remember(_mem(id: 'pref', kind: MemoryKind.semantic));
      await r.remember(_mem(id: 'rule', kind: MemoryKind.procedural));
      await r.remember(_mem(id: 'decision', kind: MemoryKind.episodic));

      final pack = await b.build(
        ownerUserId: _kOwner,
        intent: const ContextIntent(
          scope: 'options_trading',
          kindHints: {MemoryKind.semantic},
        ),
      );
      expect(pack.userPreferences.map((m) => m.id), ['pref']);
      expect(pack.applicableRules, isEmpty);
      expect(pack.relatedDecisions, isEmpty);
    });

    test('perSlotLimit caps each slot', () async {
      final b = _builder();
      final r = b.runtime;
      for (var i = 0; i < 10; i++) {
        await r.remember(_mem(id: 'rule-$i', kind: MemoryKind.procedural));
      }
      final pack = await b.build(
        ownerUserId: _kOwner,
        intent: const ContextIntent(scope: 'options_trading'),
        perSlotLimit: 3,
      );
      expect(pack.applicableRules, hasLength(3));
    });

    test('ContextPackMemory.toJson exposes all five slots', () async {
      final b = _builder();
      await b.runtime.remember(
        _mem(id: 'pref', kind: MemoryKind.semantic, scope: '*'),
      );
      final pack = await b.build(
        ownerUserId: _kOwner,
        intent: const ContextIntent(),
      );
      final json = pack.toJson();
      expect(
        json.keys,
        containsAll([
          'user_preferences',
          'recent_events',
          'related_decisions',
          'applicable_rules',
          'related_events',
        ]),
      );
    });
  });
}
