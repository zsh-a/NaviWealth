/// Shared MemoryRecord builder for the KnowledgeOS agents
/// (`docs/domains/knowledgeos-domain.md` §7).
///
/// Every agent (Review / Assumption / Contradiction / RoutineDue) emits one
/// day-keyed memory per run with identical id / scope / timestamp
/// scaffolding — only the kind, source, title, summary, payload, entities
/// and importance/confidence vary. That scaffold lived inline in each agent;
/// it is collapsed here so a new agent declares only the parts that differ.
library;

import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/format/formatters.dart';

/// Build the day-keyed memory an agent run records. Returns the record plus
/// its `memoryId` so the caller can echo the id into its `AgentRunResult`.
/// The id is stable per UTC day (`$source:YYYY-MM-DD`) so repeated runs on
/// the same day overwrite rather than pile up.
({String memoryId, MemoryRecord record}) buildAgentMemory({
  required String source,
  required MemoryKind kind,
  required String ownerUserId,
  required DateTime start,
  required DateTime finished,
  required String title,
  required String summary,
  required Map<String, Object?> payload,
  required Set<String> entities,
  required double importance,
  required double confidence,
  String scope = '*',
}) {
  final dayKey = _utcDayKey(start);
  final memoryId = '$source:$dayKey';
  return (
    memoryId: memoryId,
    record: MemoryRecord(
      id: memoryId,
      kind: kind,
      ownerUserId: ownerUserId,
      scope: scope,
      source: source,
      sourceId: dayKey,
      title: title,
      summary: summary,
      payload: payload,
      entities: entities,
      importance: importance,
      confidence: confidence,
      validFrom: start.toUtc(),
      createdAt: start.toUtc(),
      updatedAt: finished,
    ),
  );
}

String _utcDayKey(DateTime value) => AppFormatters.utcDayKey(value);
