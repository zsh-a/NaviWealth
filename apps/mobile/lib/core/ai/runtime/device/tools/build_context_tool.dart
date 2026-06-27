/// `build_context` — kind-classified context pack from the Memory
/// Runtime (`docs/architecture/lifeos-shell.md` §6, D-1.7b).
///
/// Returns a structured `{user_preferences, applicable_rules,
/// related_decisions, recent_events, related_events}` instead of flat
/// hits. Use **before** answering "did I do X before / why did I do Y
/// last time / what's my preference about Z" questions.
///
/// All slots are pre-filtered by intent (scope, entities, freeText)
/// + bounded by a per-slot limit so prompt cost is predictable.
/// Reads only — no scan / network.
library;

import 'package:naviwealth/core/auth/current_user.dart';
import '../../../contracts/context_pack_memory.dart';
import '../../../contracts/event_record.dart';
import '../../../contracts/memory_record.dart';
import '../../../local/memory/providers.dart';
import 'device_tool.dart';

class BuildContextTool implements DeviceTool {
  const BuildContextTool();

  @override
  String get name => 'build_context';

  @override
  String get description =>
      '从本地 Memory Runtime 组装"按用途分槽"的上下文包,**优先于** `query_memory` 使用。'
      '返回 5 个槽: user_preferences(长期偏好)/ applicable_rules(规则)/ '
      'related_decisions(历史决策+理由+结果)/ recent_events(最近事件流)/ '
      'related_events(按 entity 过滤后的事件)。'
      '回答涉及"以前 / 上次 / 我当时为什么 / 我的偏好是 / 是否应该"这类问题前先调用。'
      '可选 `query`(自然语言意图)、`entities`(标的列表)、`scope`(如 options_trading)、'
      '`kinds`(限制只看 semantic/episodic/procedural/event)、`per_slot_limit`(默认 6,上限 20)。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'query': <String, Object?>{
        'type': 'string',
        'description': '自然语言意图(如"是否应该卖 NVDA put");驱动 episodic 槽的语义打分。',
      },
      'entities': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
        'description': '硬实体匹配(如 ["NVDA", "put"]),提升相关条目排名 + 过滤 related_events。',
      },
      'scope': <String, Object?>{
        'type': 'string',
        'description':
            '限制 scope(如 "options_trading"),只取此 scope 下的偏好 / 规则 / 决策。',
      },
      'kinds': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{
          'type': 'string',
          'enum': ['semantic', 'episodic', 'procedural', 'event'],
        },
        'description': '只填这些 kind 对应的槽;不传则全部填。',
      },
      'per_slot_limit': <String, Object?>{
        'type': 'integer',
        'minimum': 1,
        'maximum': 20,
        'description': '每个槽的最大条数,默认 6。',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final query = (input['query'] as String?)?.trim();
    final entitiesRaw = input['entities'];
    final entities = entitiesRaw is List
        ? entitiesRaw.whereType<String>().toSet()
        : <String>{};
    final scope = (input['scope'] as String?)?.trim();
    final kindsRaw = input['kinds'];
    final kinds = kindsRaw is List
        ? kindsRaw.whereType<String>().map(MemoryKindWire.parse).toSet()
        : <MemoryKind>{};
    final perSlot = switch (input['per_slot_limit']) {
      int v => v.clamp(1, 20),
      num v => v.toInt().clamp(1, 20),
      _ => 6,
    };

    final builder = await ctx.ref.read(contextBuilderProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final pack = await builder.build(
      ownerUserId: ownerUserId,
      intent: ContextIntent(
        freeText: (query == null || query.isEmpty) ? null : query,
        entities: entities,
        scope: (scope == null || scope.isEmpty) ? null : scope,
        kindHints: kinds,
      ),
      perSlotLimit: perSlot,
    );

    final result = <String, Object?>{
      'user_preferences': pack.userPreferences
          .map(_memoryToWire)
          .toList(growable: false),
      'applicable_rules': pack.applicableRules
          .map(_memoryToWire)
          .toList(growable: false),
      'related_decisions': pack.relatedDecisions
          .map(_memoryToWire)
          .toList(growable: false),
      'recent_events': pack.recentEvents
          .map(_eventToWire)
          .toList(growable: false),
      'related_events': pack.relatedEvents
          .map(_eventToWire)
          .toList(growable: false),
    };
    if (pack.isEmpty) {
      result['guidance'] =
          '记忆库目前为空或没有匹配条目。请避免基于此结果断言"用户从未做过 X";'
          '可继续调用 read_* / get_* 工具补足上下文。';
    }
    return result;
  }

  static Map<String, Object?> _memoryToWire(
    MemoryRecord m,
  ) => <String, Object?>{
    'id': m.id,
    'kind': m.kind.wire,
    'title': m.title,
    'summary': m.summary,
    'scope': m.scope,
    if (m.source != null) 'source': m.source,
    if (m.sourceId != null) 'source_id': m.sourceId,
    if (m.entities.isNotEmpty) 'entities': m.entities.toList(growable: false),
    'importance': m.importance,
    'confidence': m.confidence,
    'payload': m.payload,
    'updated_at': m.updatedAt.toUtc().toIso8601String(),
  };

  static Map<String, Object?> _eventToWire(EventRecord e) => <String, Object?>{
    'id': e.id,
    'type': e.type,
    'timestamp': e.timestamp.toUtc().toIso8601String(),
    'source': e.source,
    if (e.title != null) 'title': e.title,
    'summary': e.summary,
    if (e.entities.isNotEmpty) 'entities': e.entities.toList(growable: false),
    'importance': e.importance,
  };
}
