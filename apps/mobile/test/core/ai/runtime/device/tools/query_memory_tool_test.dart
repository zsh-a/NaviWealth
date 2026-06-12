import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/tool_descriptor_catalog.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/query_memory_tool.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';

import '../../../../../core/persistence/test_database.dart';

const _kOwner = 'u1';

Future<MemoryRuntime> _seededRuntime(List<MemoryRecord> seed) async {
  final db = makeTestDatabase();
  final rt = MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
  for (final m in seed) {
    await rt.remember(m);
  }
  return rt;
}

MemoryRecord _mem({
  required String id,
  MemoryKind kind = MemoryKind.episodic,
  String scope = 'options_trading',
  String title = '',
  String summary = '',
  String? source,
  Set<String> entities = const {},
  double importance = 0.6,
}) => MemoryRecord(
  id: id,
  kind: kind,
  ownerUserId: _kOwner,
  scope: scope,
  source: source,
  title: title.isEmpty ? id : title,
  summary: summary.isEmpty ? id : summary,
  payload: const {},
  entities: entities,
  importance: importance,
  confidence: 0.85,
  createdAt: DateTime.utc(2026, 5, 24),
  updatedAt: DateTime.utc(2026, 5, 24),
);

ProviderContainer _container(MemoryRuntime runtime) => ProviderContainer(
  overrides: [
    memoryRuntimeProvider.overrideWith((ref) async => runtime),
    currentUserIdProvider.overrideWithValue(() async => _kOwner),
  ],
);

Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
}

Future<Map<String, Object?>> _invoke(
  ProviderContainer container,
  Map<String, Object?> input,
) {
  const tool = QueryMemoryTool();
  return _withRef(container, (ref) async {
    final out = await tool.invoke(
      DeviceToolContext(
        ref: ref,
        session: DeviceSession(messages: const <AnthropicChatMessage>[]),
      ),
      input,
    );
    return (out! as Map).cast<String, Object?>();
  });
}

void main() {
  group('QueryMemoryTool', () {
    const tool = QueryMemoryTool();

    test('descriptor mirror match (registry + catalog)', () {
      expect(tool.name, 'query_memory');
      expect(tool.inputSchema['required'], <String>['query']);
      final descriptor = lookupToolDescriptor('query_memory');
      expect(descriptor, isNotNull);
      expect(descriptor!.access, Access.read);
      expect(descriptor.sideEffect, SideEffect.none);
    });

    test('returns hits with hybrid score breakdown', () async {
      final rt = await _seededRuntime([
        _mem(
          id: 'a',
          source: 'options_trade_journal',
          summary: 'sold NVDA cash secured put because long term bullish',
          entities: const {'NVDA'},
        ),
        _mem(
          id: 'b',
          source: 'options_trade_journal',
          summary: 'AAPL covered call hedge',
          entities: const {'AAPL'},
        ),
      ]);
      final c = _container(rt);
      addTearDown(c.dispose);

      final out = await _invoke(c, <String, Object?>{
        'query': 'NVDA put bullish',
      });
      final hits = out['hits'] as List<Object?>;
      expect(hits, isNotEmpty);
      final first = (hits.first as Map).cast<String, Object?>();
      expect(first['kind'], 'episodic');
      expect(first['source'], 'options_trade_journal');
      expect(first['score'], isA<num>());
      expect(first['semantic_sim'], isA<num>());
      expect(first['entity_overlap'], isA<num>());
      expect(first['recency'], isA<num>());
    });

    test('returns empty hits + guidance when nothing indexed', () async {
      final rt = await _seededRuntime(const []);
      final c = _container(rt);
      addTearDown(c.dispose);

      final out = await _invoke(c, <String, Object?>{'query': 'anything'});
      expect(out['hits'], isEmpty);
      expect(out['guidance'], isNotNull);
    });

    test('source filter restricts hits', () async {
      final rt = await _seededRuntime([
        _mem(
          id: 'a',
          source: 'options_trade_journal',
          summary: 'NVDA put bullish thesis',
        ),
        _mem(
          id: 'b',
          source: 'note',
          summary: 'NVDA bullish reading from blog post',
        ),
      ]);
      final c = _container(rt);
      addTearDown(c.dispose);

      final out = await _invoke(c, <String, Object?>{
        'query': 'NVDA bullish',
        'source': 'options_trade_journal',
      });
      final hits = out['hits'] as List<Object?>;
      expect(
        hits.map((h) => (h as Map)['source']),
        everyElement('options_trade_journal'),
      );
    });

    test('kind filter restricts hits', () async {
      final rt = await _seededRuntime([
        _mem(
          id: 'rule',
          kind: MemoryKind.procedural,
          summary: 'close when 70% captured',
        ),
        _mem(
          id: 'decision',
          kind: MemoryKind.episodic,
          summary: 'closed when 70% captured',
        ),
      ]);
      final c = _container(rt);
      addTearDown(c.dispose);

      final out = await _invoke(c, <String, Object?>{
        'query': '70% captured',
        'kind': 'procedural',
      });
      final hits = out['hits'] as List<Object?>;
      expect(hits.map((h) => (h as Map)['kind']), everyElement('procedural'));
    });

    test('top_k is clamped to [1, 20]', () async {
      final seed = [
        for (var i = 0; i < 25; i++)
          _mem(id: 'm-$i', summary: 'apple banana entry $i'),
      ];
      final rt = await _seededRuntime(seed);
      final c = _container(rt);
      addTearDown(c.dispose);

      final tooHigh = await _invoke(c, <String, Object?>{
        'query': 'apple banana',
        'top_k': 999,
      });
      expect((tooHigh['hits'] as List).length, lessThanOrEqualTo(20));

      final tooLow = await _invoke(c, <String, Object?>{
        'query': 'apple banana',
        'top_k': -5,
      });
      expect((tooLow['hits'] as List).length, 1);
    });

    test('rejects empty / non-string query with invalid_input', () async {
      final rt = await _seededRuntime([_mem(id: 'x')]);
      final c = _container(rt);
      addTearDown(c.dispose);

      final blank = await _invoke(c, const <String, Object?>{'query': '   '});
      expect(blank['code'], 'invalid_input');
      final wrongType = await _invoke(c, const <String, Object?>{'query': 42});
      expect(wrongType['code'], 'invalid_input');
    });
  });
}
