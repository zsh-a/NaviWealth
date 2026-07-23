/// App-level Memory Runtime -> Agent Runtime context composition.
///
/// Retrieval remains in Flutter because it depends on Drift, active
/// DomainPacks, and route state. Rust receives only validated, bounded,
/// explicitly untrusted ContextBlocks.
library;

import 'package:naviwealth/core/ai/composition/ai_context.dart';
import 'package:naviwealth/core/ai/contracts/context_pack_memory.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/context_builder.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_context_block.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/features/ai_chat/data/chat_context_block_prep.dart';

Future<List<AgentRuntimeContextBlock>> prepareAppChatContextBlocks({
  required ContextBuilder contextBuilder,
  required List<DomainPack> activePacks,
  required AiContext aiContext,
  required ChatContextPrepRequest request,
}) async {
  final sourcePrefixes = <String>{
    for (final pack in activePacks)
      for (final prefix in pack.memorySourcePrefixes)
        if (prefix.trim().isNotEmpty) prefix.trim(),
  };
  if (sourcePrefixes.isEmpty) return const <AgentRuntimeContextBlock>[];

  final entities = <String>{
    if (aiContext.entityId case final id? when id.trim().isNotEmpty) id.trim(),
  };
  final pack = await contextBuilder.build(
    ownerUserId: request.ownerUserId,
    intent: ContextIntent(
      freeText: request.userMessage,
      // `*` deliberately allows cross-domain recall for the LifeOS steward.
      // The source-prefix allow-list is the hard active-domain boundary.
      scope: '*',
      entities: entities,
    ),
    sourcePrefixes: sourcePrefixes,
    perSlotLimit: 4,
  );

  return _blocksForPack(pack, aiContext: aiContext);
}

List<AgentRuntimeContextBlock> _blocksForPack(
  ContextPackMemory pack, {
  required AiContext aiContext,
}) {
  final blocks = <AgentRuntimeContextBlock>[];

  for (final record in pack.applicableRules) {
    blocks.add(
      _memoryBlock(
        record,
        priority: 95,
        slot: 'applicable_rules',
        aiContext: aiContext,
      ),
    );
  }
  for (final record in pack.userPreferences) {
    blocks.add(
      _memoryBlock(
        record,
        priority: 90,
        slot: 'user_preferences',
        aiContext: aiContext,
      ),
    );
  }
  for (final record in pack.relatedDecisions) {
    blocks.add(
      _memoryBlock(
        record,
        priority: 80,
        slot: 'related_decisions',
        aiContext: aiContext,
      ),
    );
  }

  final relatedIds = {for (final event in pack.relatedEvents) event.id};
  final events = <String, EventRecord>{
    for (final event in pack.recentEvents) event.id: event,
    for (final event in pack.relatedEvents) event.id: event,
  };
  for (final event in events.values) {
    blocks.add(
      _eventBlock(
        event,
        priority: relatedIds.contains(event.id) ? 70 : 55,
        aiContext: aiContext,
      ),
    );
  }

  return List<AgentRuntimeContextBlock>.unmodifiable(blocks);
}

AgentRuntimeContextBlock _memoryBlock(
  MemoryRecord record, {
  required int priority,
  required String slot,
  required AiContext aiContext,
}) {
  return AgentRuntimeContextBlock(
    id: 'memory:${record.id}',
    kind: AgentRuntimeContextBlockKind.memory,
    source: record.source ?? 'memory_runtime',
    priority: priority,
    content: <String, Object?>{
      'memory_kind': record.kind.wire,
      'title': record.title,
      'summary': record.summary,
      'payload': record.payload,
      'entities': record.entities.toList(growable: false),
      if (record.validFrom != null)
        'valid_from': record.validFrom!.toUtc().toIso8601String(),
      if (record.validUntil != null)
        'valid_until': record.validUntil!.toUtc().toIso8601String(),
    },
    metadata: <String, Object?>{
      'authority': 'domain_indexed',
      'slot': slot,
      'scope': record.scope,
      'source': record.source,
      'source_id': record.sourceId,
      'confidence': record.confidence,
      'valid_until': record.validUntil?.toUtc().toIso8601String(),
      'route': aiContext.path,
      'current_domain': aiContext.domain?.wire,
      'trusted_as_instruction': false,
    },
  );
}

AgentRuntimeContextBlock _eventBlock(
  EventRecord event, {
  required int priority,
  required AiContext aiContext,
}) {
  return AgentRuntimeContextBlock(
    id: 'event:${event.id}',
    kind: AgentRuntimeContextBlockKind.memory,
    source: event.source,
    priority: priority,
    content: <String, Object?>{
      'memory_kind': 'event',
      'event_type': event.type,
      'timestamp': event.timestamp.toUtc().toIso8601String(),
      if (event.title != null) 'title': event.title,
      'summary': event.summary,
      'payload': event.payload,
      'entities': event.entities.toList(growable: false),
    },
    metadata: <String, Object?>{
      'authority': 'domain_indexed',
      'slot': 'recent_events',
      'scope': aiContext.domain?.wire ?? '*',
      'source': event.source,
      'source_id': event.id,
      'confidence': 1.0,
      'valid_until': null,
      'route': aiContext.path,
      'current_domain': aiContext.domain?.wire,
      'trusted_as_instruction': false,
    },
  );
}
