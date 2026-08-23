/// App-level Memory Runtime -> Agent Runtime context composition.
///
/// Retrieval remains in Flutter because it depends on Drift, active
/// DomainPacks, and route state. Rust receives only validated, bounded,
/// explicitly untrusted ContextBlocks.
library;

import 'package:naviwealth/core/ai/composition/ai_context.dart';
import 'package:naviwealth/core/ai/contracts/context_evidence.dart';
import 'package:naviwealth/core/ai/contracts/context_pack_memory.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/context_builder.dart';
import 'package:naviwealth/core/ai/local/memory/memory_access_policy.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_context_block.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_fact.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_snapshot.dart';
import 'package:naviwealth/features/ai_chat/data/chat_context_block_prep.dart';

Future<List<AgentRuntimeContextBlock>> prepareAppChatContextBlocks({
  required ContextBuilder contextBuilder,
  required MemoryAccessPolicy accessPolicy,
  required PersonalProfileSnapshotBuilder profileBuilder,
  required Set<String> activeDomainScopes,
  required AiContext aiContext,
  required ChatContextPrepRequest request,
}) async {
  final sourcePrefixes = accessPolicy.sourcePrefixes;
  final entities = <String>{
    if (aiContext.entityId case final id? when id.trim().isNotEmpty) id.trim(),
  };
  final profile = await profileBuilder.build(
    ownerUserId: request.ownerUserId,
    activeDomainScopes: activeDomainScopes,
  );
  final pack = sourcePrefixes.isEmpty
      ? const ContextPackMemory(
          userPreferences: <MemoryRecord>[],
          recentEvents: <EventRecord>[],
          relatedDecisions: <MemoryRecord>[],
          relatedEpisodes: <MemoryRecord>[],
          derivedPatterns: <MemoryRecord>[],
          derivedGuidance: <MemoryRecord>[],
          applicableRules: <MemoryRecord>[],
          relatedEvents: <EventRecord>[],
        )
      : await contextBuilder.build(
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

  return <AgentRuntimeContextBlock>[
    for (final fact in profile.facts) _profileBlock(fact, aiContext: aiContext),
    ..._blocksForPack(pack, aiContext: aiContext),
  ];
}

AgentRuntimeContextBlock _profileBlock(
  PersonalProfileFact fact, {
  required AiContext aiContext,
}) {
  final priority = switch (fact.kind) {
    PersonalProfileFactKind.constraint => 110,
    PersonalProfileFactKind.rule => 105,
    PersonalProfileFactKind.goal => 100,
    PersonalProfileFactKind.preference => 95,
  };
  return AgentRuntimeContextBlock(
    id: 'profile:${fact.id}',
    kind: AgentRuntimeContextBlockKind.profile,
    source: fact.provenance.source ?? 'personal_profile',
    priority: priority,
    content: <String, Object?>{
      'profile_kind': fact.kind.wire,
      'key': fact.key,
      'value': fact.value,
      'summary': fact.summary,
      if (fact.domainScope != null) 'domain_scope': fact.domainScope,
      'confidence': fact.confidence,
    },
    evidence: AgentRuntimeContextEvidence(
      authority: fact.authority,
      provenance: fact.provenance,
      validFrom: fact.validFrom,
      validUntil: fact.validUntil,
      supersedes: fact.supersedesFactId == null
          ? null
          : 'profile:${fact.supersedesFactId}',
    ),
    metadata: <String, Object?>{
      'slot': 'personal_profile',
      'route': aiContext.path,
      'current_domain': aiContext.domain?.wire,
      'trusted_as_instruction': false,
    },
  );
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
  for (final record in pack.relatedEpisodes) {
    blocks.add(
      _memoryBlock(
        record,
        priority: 75,
        slot: 'related_episodes',
        aiContext: aiContext,
      ),
    );
  }
  for (final record in pack.derivedPatterns) {
    blocks.add(
      _memoryBlock(
        record,
        priority: 70,
        slot: 'derived_patterns',
        aiContext: aiContext,
      ),
    );
  }
  for (final record in pack.derivedGuidance) {
    blocks.add(
      _memoryBlock(
        record,
        priority: 65,
        slot: 'derived_guidance',
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
    evidence: AgentRuntimeContextEvidence(
      authority: record.authority,
      provenance: record.provenance,
      validFrom: record.validFrom,
      validUntil: record.validUntil,
      supersedes: record.supersedesId == null
          ? null
          : 'memory:${record.supersedesId}',
    ),
    metadata: <String, Object?>{
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
    source: event.sourceIdentity.rowFamily,
    priority: priority,
    content: <String, Object?>{
      'memory_kind': 'event',
      if (event.domain != null) 'domain': event.domain!.wire,
      'event_kind': event.kind.wire,
      'occurred_at': event.occurredAt.toUtc().toIso8601String(),
      'observed_at': event.observedAt.toUtc().toIso8601String(),
      if (event.title != null) 'title': event.title,
      'summary': event.summary,
      'facts': event.facts,
      'entities': event.entities.toList(growable: false),
      'source_identity': event.sourceIdentity.toJson(),
      'confidence': event.confidence,
    },
    evidence: AgentRuntimeContextEvidence(
      authority: EvidenceAuthority.sourceFact,
      provenance: EvidenceProvenance(
        source: event.sourceIdentity.rowFamily,
        sourceId: event.sourceIdentity.rowId,
        observedAt: event.observedAt,
      ),
      validFrom: event.occurredAt,
    ),
    metadata: <String, Object?>{
      'slot': 'recent_events',
      'scope': aiContext.domain?.wire ?? '*',
      'source_family': event.sourceIdentity.rowFamily,
      'source_id': event.sourceIdentity.rowId,
      'source_fingerprint': event.sourceIdentity.fingerprint,
      'confidence': event.confidence,
      'valid_until': null,
      'route': aiContext.path,
      'current_domain': aiContext.domain?.wire,
      'trusted_as_instruction': false,
    },
  );
}
