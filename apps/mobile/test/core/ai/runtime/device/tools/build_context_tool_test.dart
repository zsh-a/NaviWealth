import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/context_builder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/build_context_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/data/repositories/mutation_context.dart';

import '../../../../../data/db/test_database.dart';

const _kOwner = 'u1';

Future<MemoryRuntime> _newRuntime() async {
  final db = makeTestDatabase();
  return MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
}

ProviderContainer _container(MemoryRuntime runtime) => ProviderContainer(
  overrides: [
    memoryRuntimeProvider.overrideWith((ref) async => runtime),
    contextBuilderProvider.overrideWith(
      (ref) async => ContextBuilder(runtime: runtime),
    ),
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
  const tool = BuildContextTool();
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

MemoryRecord _mem({
  required String id,
  required MemoryKind kind,
  String scope = 'options_trading',
  String title = '',
  String summary = '',
  Set<String> entities = const {},
}) => MemoryRecord(
  id: id,
  kind: kind,
  ownerUserId: _kOwner,
  scope: scope,
  source: 'test',
  title: title.isEmpty ? id : title,
  summary: summary.isEmpty ? id : summary,
  payload: const {},
  entities: entities,
  importance: 0.6,
  confidence: 0.85,
  createdAt: DateTime.utc(2026, 5, 24),
  updatedAt: DateTime.utc(2026, 5, 24),
);

void main() {
  group('BuildContextTool', () {
    const tool = BuildContextTool();

    test('descriptor mirror match', () {
      expect(tool.name, 'build_context');
      final descriptor = lookupToolDescriptor('build_context');
      expect(descriptor, isNotNull);
      expect(descriptor!.access, Access.read);
      expect(descriptor.sideEffect, SideEffect.none);
    });

    test('returns five labeled slots + guidance when empty', () async {
      final rt = await _newRuntime();
      final c = _container(rt);
      addTearDown(c.dispose);

      final out = await _invoke(c, const <String, Object?>{});
      expect(
        out.keys,
        containsAll([
          'user_preferences',
          'applicable_rules',
          'related_decisions',
          'recent_events',
          'related_events',
        ]),
      );
      expect(out['guidance'], isNotNull);
    });

    test('classifies records into the right slot', () async {
      final rt = await _newRuntime();
      await rt.remember(
        _mem(id: 'pref', kind: MemoryKind.semantic, scope: '*'),
      );
      await rt.remember(_mem(id: 'rule', kind: MemoryKind.procedural));
      await rt.remember(
        _mem(id: 'decision', kind: MemoryKind.episodic, summary: 'NVDA put'),
      );
      await rt.recordEvent(
        EventRecord(
          id: 'event-1',
          type: 'trade_closed',
          timestamp: DateTime.utc(2026, 5, 23),
          source: 'options_trade_journal',
          ownerUserId: _kOwner,
          summary: 'closed NVDA put',
          payload: const {},
          entities: const {'NVDA'},
        ),
      );

      final c = _container(rt);
      addTearDown(c.dispose);

      final out = await _invoke(c, <String, Object?>{
        'query': 'NVDA put',
        'scope': 'options_trading',
        'entities': <String>['NVDA'],
      });
      expect((out['user_preferences'] as List).length, 1);
      expect((out['applicable_rules'] as List).length, 1);
      expect((out['related_decisions'] as List).length, 1);
      expect((out['recent_events'] as List).length, 1);
      expect((out['related_events'] as List).length, 1);
    });

    test('per_slot_limit caps each slot', () async {
      final rt = await _newRuntime();
      for (var i = 0; i < 10; i++) {
        await rt.remember(_mem(id: 'r-$i', kind: MemoryKind.procedural));
      }
      final c = _container(rt);
      addTearDown(c.dispose);

      final out = await _invoke(c, <String, Object?>{
        'scope': 'options_trading',
        'per_slot_limit': 3,
      });
      expect((out['applicable_rules'] as List).length, 3);
    });

    test('kinds restricts which slots are populated', () async {
      final rt = await _newRuntime();
      await rt.remember(_mem(id: 'pref', kind: MemoryKind.semantic));
      await rt.remember(_mem(id: 'rule', kind: MemoryKind.procedural));

      final c = _container(rt);
      addTearDown(c.dispose);

      final out = await _invoke(c, <String, Object?>{
        'scope': 'options_trading',
        'kinds': <String>['semantic'],
      });
      expect((out['user_preferences'] as List).length, 1);
      expect((out['applicable_rules'] as List), isEmpty);
    });

    test('per_slot_limit is clamped to [1, 20]', () async {
      final rt = await _newRuntime();
      for (var i = 0; i < 30; i++) {
        await rt.remember(_mem(id: 'r-$i', kind: MemoryKind.procedural));
      }
      final c = _container(rt);
      addTearDown(c.dispose);

      final tooHigh = await _invoke(c, <String, Object?>{
        'scope': 'options_trading',
        'per_slot_limit': 999,
      });
      expect(
        (tooHigh['applicable_rules'] as List).length,
        lessThanOrEqualTo(20),
      );

      final tooLow = await _invoke(c, <String, Object?>{
        'scope': 'options_trading',
        'per_slot_limit': -5,
      });
      expect((tooLow['applicable_rules'] as List).length, 1);
    });
  });
}
