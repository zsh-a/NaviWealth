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

import 'package:naviwealth/core/ai/contracts/context_evidence.dart';
import 'package:naviwealth/core/ai/contracts/context_pack_memory.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_fact.dart';
import 'package:naviwealth/core/lifeos/personal_profile/providers.dart';

import 'device_tool.dart';

class BuildContextTool implements DeviceTool {
  const BuildContextTool();

  @override
  String get name => 'build_context';

  @override
  String get description =>
      '从本地 Memory Runtime 组装"按用途分槽"的上下文包,**优先于** `query_memory` 使用。'
      '返回 personal_profile(用户确认的目标/偏好/约束/规则)以及 '
      'user_preferences(旧长期偏好)/ applicable_rules(旧规则)/ '
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
    final accessPolicy = ctx.ref.read(memoryAccessPolicyProvider);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final profileBuilder = await ctx.ref.read(
      personalProfileSnapshotBuilderProvider.future,
    );
    final profile = await profileBuilder.build(
      ownerUserId: ownerUserId,
      activeDomainScopes: ctx.ref.read(
        activePersonalProfileDomainScopesProvider,
      ),
    );
    final pack = await builder.build(
      ownerUserId: ownerUserId,
      intent: ContextIntent(
        freeText: (query == null || query.isEmpty) ? null : query,
        entities: entities,
        scope: (scope == null || scope.isEmpty) ? null : scope,
        kindHints: kinds,
      ),
      sourcePrefixes: accessPolicy.sourcePrefixes,
      perSlotLimit: perSlot,
    );

    final result = <String, Object?>{
      'personal_profile': profile.facts
          .map(_profileToWire)
          .toList(growable: false),
      'user_preferences': pack.userPreferences
          .map(_memoryToWire)
          .toList(growable: false),
      'applicable_rules': pack.applicableRules
          .map(_memoryToWire)
          .toList(growable: false),
      'related_decisions': pack.relatedDecisions
          .map(_memoryToWire)
          .toList(growable: false),
      'related_episodes': pack.relatedEpisodes
          .map(_memoryToWire)
          .toList(growable: false),
      'derived_patterns': pack.derivedPatterns
          .map(_memoryToWire)
          .toList(growable: false),
      'derived_guidance': pack.derivedGuidance
          .map(_memoryToWire)
          .toList(growable: false),
      'recent_events': pack.recentEvents
          .map(_eventToWire)
          .toList(growable: false),
      'related_events': pack.relatedEvents
          .map(_eventToWire)
          .toList(growable: false),
    };
    if (pack.isEmpty && profile.isEmpty) {
      result['guidance'] =
          '记忆库目前为空或没有匹配条目。请避免基于此结果断言"用户从未做过 X";'
          '可继续调用 read_* / get_* 工具补足上下文。';
    }
    return result;
  }

  static Map<String, Object?> _profileToWire(PersonalProfileFact fact) =>
      <String, Object?>{
        'id': fact.id,
        'kind': fact.kind.wire,
        'key': fact.key,
        'value': fact.value,
        'summary': fact.summary,
        if (fact.domainScope != null) 'domain_scope': fact.domainScope,
        'authority': fact.authority.wire,
        'provenance': fact.provenance.toJson(),
        'confidence': fact.confidence,
        'valid_from': fact.validFrom.toUtc().toIso8601String(),
        if (fact.validUntil != null)
          'valid_until': fact.validUntil!.toUtc().toIso8601String(),
        if (fact.supersedesFactId != null) 'supersedes': fact.supersedesFactId,
      };

  static Map<String, Object?> _memoryToWire(
    MemoryRecord m,
  ) => <String, Object?>{
    'id': m.id,
    'kind': m.kind.wire,
    'role': m.role.wire,
    'authority': m.authority.wire,
    'provenance': m.provenance.toJson(),
    'title': m.title,
    'summary': m.summary,
    'scope': m.scope,
    if (m.source != null) 'source': m.source,
    if (m.sourceId != null) 'source_id': m.sourceId,
    if (m.entities.isNotEmpty) 'entities': m.entities.toList(growable: false),
    'importance': m.importance,
    'confidence': m.confidence,
    'payload': m.payload,
    if (m.validFrom != null)
      'valid_from': m.validFrom!.toUtc().toIso8601String(),
    if (m.validUntil != null)
      'valid_until': m.validUntil!.toUtc().toIso8601String(),
    if (m.supersedesId != null) 'supersedes': m.supersedesId,
    'updated_at': m.updatedAt.toUtc().toIso8601String(),
  };

  static Map<String, Object?> _eventToWire(EventRecord e) => <String, Object?>{
    'id': e.id,
    if (e.domain != null) 'domain': e.domain!.wire,
    'kind': e.kind.wire,
    'occurred_at': e.occurredAt.toUtc().toIso8601String(),
    'observed_at': e.observedAt.toUtc().toIso8601String(),
    'source_identity': e.sourceIdentity.toJson(),
    'authority': EvidenceAuthority.sourceFact.wire,
    'provenance': EvidenceProvenance(
      source: e.sourceIdentity.rowFamily,
      sourceId: e.sourceIdentity.rowId,
      observedAt: e.observedAt,
    ).toJson(),
    if (e.title != null) 'title': e.title,
    'summary': e.summary,
    'facts': e.facts,
    if (e.entities.isNotEmpty) 'entities': e.entities.toList(growable: false),
    'importance': e.importance,
    'confidence': e.confidence,
  };
}
