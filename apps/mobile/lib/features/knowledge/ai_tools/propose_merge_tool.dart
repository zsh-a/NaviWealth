/// `propose_merge` — KnowledgeOS dedupe write tool
/// (`docs/knowledgeos-domain.md` §15.3).
///
/// **Write semantics**: returns a proposal envelope; the user confirms in
/// the UI (one-tap, with the merge diff rendered in the card) before any
/// row moves. Matches the cross-domain `propose_*` pattern.
///
/// MVP merges only Note↔Note and Concept↔Concept (the types with few /
/// no inbound id references). On confirm the applier calls
/// `KnowledgeRepository.mergeNotes` / `mergeConcepts`: the survivor unions
/// tags (+ aliases / related ids for concepts), the duplicates are
/// soft-deleted and stamped `mergedIntoId = primary`. Reversible — that
/// is why one-tap (not a typed confirm) is the right friction level.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../data/providers.dart';
import '_tool_support.dart';

class ProposeMergeTool implements DeviceTool {
  const ProposeMergeTool();

  @override
  String get name => 'propose_merge';

  @override
  String get description =>
      '建议把若干条重复的 KnowledgeOS 条目合并为一条。**不会**直接写库,返回 proposal envelope,'
      '前端显示合并 diff 让用户一键确认。'
      'entity_type 只支持 note / concept(MVP)。primary_id 为保留的那条;'
      'duplicate_ids 为被合并(合并后软删)的条目。'
      '可选 merged_title / merged_body(note)或 merged_name / merged_summary(concept)覆盖保留条目的字段;'
      '不传则沿用 primary 的字段、并并集 tags(concept 另并集 aliases / related)。'
      '通常先用 find_similar_knowledge 找到候选,再调用本工具。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'entity_type': {
        'type': 'string',
        'enum': <String>['note', 'concept'],
      },
      'primary_id': {
        'type': 'string',
        'description': '保留的条目 id。',
      },
      'duplicate_ids': {
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
        'minItems': 1,
        'description': '要合并进 primary 的重复条目 id(至少一个)。',
      },
      'merged_title': {'type': 'string', 'description': 'note: 覆盖保留条目标题。'},
      'merged_body': {'type': 'string', 'description': 'note: 覆盖保留条目正文。'},
      'merged_name': {'type': 'string', 'description': 'concept: 覆盖名称。'},
      'merged_summary': {'type': 'string', 'description': 'concept: 覆盖摘要。'},
      'reason': {
        'type': 'string',
        'description': '一句中文说明为什么判定它们重复。会显示给用户。',
      },
    },
    'required': <String>['entity_type', 'primary_id', 'duplicate_ids', 'reason'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final entityType = (input['entity_type'] as String?)?.trim() ?? '';
    final primaryId = (input['primary_id'] as String?)?.trim() ?? '';
    final dupRaw = input['duplicate_ids'];
    final duplicateIds = dupRaw is List
        ? dupRaw
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty && s != primaryId)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    final reason = (input['reason'] as String?)?.trim() ?? '';

    if (entityType != 'note' && entityType != 'concept') {
      return badRequest('entity_type 只支持 note / concept。');
    }
    if (primaryId.isEmpty || reason.isEmpty || duplicateIds.isEmpty) {
      return badRequest(
        'primary_id / reason 必填,duplicate_ids 至少一个(且不等于 primary_id)。',
      );
    }

    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);

    // Hydrate so the card can show a real diff and we can fail fast on a
    // dangling id rather than letting the apply path discover it.
    final missing = <String>[];
    final keptLabel = <String, Object?>{};
    final removedLabels = <String>[];
    final mergedTags = <String>{};

    if (entityType == 'note') {
      final primary = await repo.findNote(primaryId);
      if (primary == null) {
        missing.add(primaryId);
      } else {
        keptLabel['title'] = primary.title;
        mergedTags.addAll(primary.tags);
      }
      for (final id in duplicateIds) {
        final d = await repo.findNote(id);
        if (d == null) {
          missing.add(id);
        } else {
          removedLabels.add(d.title);
          mergedTags.addAll(d.tags);
        }
      }
    } else {
      final primary = await repo.findConcept(primaryId);
      if (primary == null) {
        missing.add(primaryId);
      } else {
        keptLabel['title'] = primary.name;
        mergedTags.addAll(primary.aliases);
      }
      for (final id in duplicateIds) {
        final d = await repo.findConcept(id);
        if (d == null) {
          missing.add(id);
        } else {
          removedLabels.add(d.name);
          mergedTags
            ..addAll(d.aliases)
            ..add(d.name);
        }
      }
    }

    if (missing.isNotEmpty) {
      return notFound('以下 id 不存在或已删除: ${missing.join(', ')}', missing);
    }

    final kept = keptLabel['title'] as String? ?? primaryId;
    final summary =
        '建议合并 ${duplicateIds.length} 条${entityType == 'note' ? '笔记' : '概念'}'
        '到「$kept」— $reason';

    return proposalEnvelope(
      kind: 'knowledge_merge',
      summaryZh: summary,
      payload: <String, Object?>{
        'entity_type': entityType,
        'primary_id': primaryId,
        'duplicate_ids': duplicateIds,
        'merged_title': (input['merged_title'] as String?)?.trim(),
        'merged_body': (input['merged_body'] as String?)?.trim(),
        'merged_name': (input['merged_name'] as String?)?.trim(),
        'merged_summary': (input['merged_summary'] as String?)?.trim(),
        'reason': reason,
        // Rendered in the one-tap card so the user sees what survives /
        // disappears before confirming (§15.3 — diff is a render concern).
        'diff': <String, Object?>{
          'kept': kept,
          'removed': removedLabels,
          'merged_tags': mergedTags.toList(growable: false),
        },
      },
      note:
          '前端必须显示 summary_zh + diff 给用户确认；只有用户明确点确认后才走 '
          'KnowledgeRepository.mergeNotes / mergeConcepts。合并可逆(被合并条目软删并记 mergedIntoId)。',
    );
  }
}
