import 'package:uuid/uuid.dart';

import '../../../../auth/providers.dart';
import '../../../composition/proposal_envelope.dart';
import '../../../contracts/memory_candidate.dart';
import '../../../contracts/memory_record.dart';
import '../../../local/memory/providers.dart';
import 'device_tool.dart';

const Uuid _uuid = Uuid();

/// Stages a user-reviewable long-term-memory change.
///
/// Invoking this tool writes only `memory_candidates`; it never writes the
/// authoritative `memories` table. The matching ProposalEnvelope must be
/// confirmed before [MemoryProposalApplier] materializes the change.
final class ProposeMemoryTool implements DeviceTool {
  const ProposeMemoryTool();

  @override
  String get name => 'propose_memory';

  @override
  String get description =>
      '提出一项长期记忆变更（新建、替代或忘记）。只允许用于用户明确表达且未来仍有用的'
      '偏好、目标、约束、决策理由或规则；不要根据一次性问题自行推断。调用只创建待确认'
      '候选，不会写入正式 Memory。用户必须在提案卡片上确认。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'additionalProperties': false,
    'properties': <String, Object?>{
      'operation': <String, Object?>{
        'type': 'string',
        'enum': <String>['create', 'supersede', 'forget'],
      },
      'memory_kind': <String, Object?>{
        'type': 'string',
        'enum': <String>['semantic', 'episodic', 'procedural'],
        'description': 'create/supersede 时必填。',
      },
      'title': <String, Object?>{
        'type': 'string',
        'description': '简短、可独立理解的记忆标题。',
      },
      'summary': <String, Object?>{
        'type': 'string',
        'description': '稠密、自包含且不添加用户未确认信息的摘要。',
      },
      'scope': <String, Object?>{
        'type': 'string',
        'description': '适用范围；跨域偏好用 *。',
        'default': '*',
      },
      'entities': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
      'payload': <String, Object?>{
        'type': 'object',
        'description': '结构化事实、理由、条件或动作；不得包含秘密。',
      },
      'importance': <String, Object?>{
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
        'default': 0.8,
      },
      'target_memory_id': <String, Object?>{
        'type': 'string',
        'description': 'supersede/forget 时必填，必须来自 query_memory。',
      },
      'valid_from': <String, Object?>{
        'type': 'string',
        'description': '可选 ISO-8601 生效时间。',
      },
      'valid_until': <String, Object?>{
        'type': 'string',
        'description': '可选 ISO-8601 失效时间。',
      },
      'reason': <String, Object?>{
        'type': 'string',
        'description': '为什么这项变更值得长期保留或移除。',
      },
    },
    'required': <String>['operation', 'reason'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final session = ctx.ref.read(authSessionProvider);
    if (session == null || session.userId.trim().isEmpty) {
      return proposalBadRequest('当前没有可用的本地用户会话。');
    }
    final operation = MemoryCandidateOperationWire.tryParse(
      (input['operation'] as String?)?.trim(),
    );
    final reason = (input['reason'] as String?)?.trim() ?? '';
    if (operation == null || reason.isEmpty) {
      return proposalBadRequest('operation / reason 必填。');
    }

    final targetMemoryId = (input['target_memory_id'] as String?)?.trim() ?? '';
    String? targetTitle;
    if (operation != MemoryCandidateOperation.create) {
      if (targetMemoryId.isEmpty) {
        return proposalBadRequest('supersede/forget 必须提供 target_memory_id。');
      }
      final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
      final prior = await runtime.memoryStore.readMemory(targetMemoryId);
      if (prior == null || prior.ownerUserId != session.userId) {
        return proposalNotFound('找不到可变更的长期记忆。', <String>[targetMemoryId]);
      }
      targetTitle = prior.title;
    }

    final payload = <String, Object?>{
      'operation': operation.wire,
      if (targetMemoryId.isNotEmpty) 'target_memory_id': targetMemoryId,
      'reason': reason,
    };
    if (operation != MemoryCandidateOperation.forget) {
      final kind = MemoryKindWire.parse(
        (input['memory_kind'] as String?)?.trim() ?? '',
      );
      final kindWire = (input['memory_kind'] as String?)?.trim() ?? '';
      final title = (input['title'] as String?)?.trim() ?? '';
      final summary = (input['summary'] as String?)?.trim() ?? '';
      if (!const <String>{
            'semantic',
            'episodic',
            'procedural',
          }.contains(kindWire) ||
          kind == MemoryKind.event ||
          title.isEmpty ||
          summary.isEmpty) {
        return proposalBadRequest(
          'create/supersede 必须提供 semantic/episodic/procedural、title 和 summary。',
        );
      }
      final entitiesRaw = input['entities'];
      final entities = entitiesRaw is List
          ? entitiesRaw
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(growable: false)
          : const <String>[];
      final memoryPayloadRaw = input['payload'];
      final memoryPayload = memoryPayloadRaw is Map
          ? memoryPayloadRaw.map((key, value) => MapEntry('$key', value))
          : const <String, Object?>{};
      final importance = ((input['importance'] as num?)?.toDouble() ?? 0.8)
          .clamp(0.0, 1.0);
      final validFrom = _optionalDate(input['valid_from']);
      final validUntil = _optionalDate(input['valid_until']);
      if (input['valid_from'] != null && validFrom == null ||
          input['valid_until'] != null && validUntil == null) {
        return proposalBadRequest('valid_from / valid_until 必须是 ISO-8601。');
      }
      if (validFrom != null &&
          validUntil != null &&
          !validUntil.isAfter(validFrom)) {
        return proposalBadRequest('valid_until 必须晚于 valid_from。');
      }
      payload.addAll(<String, Object?>{
        'memory_id': 'user_memory:${_uuid.v4()}',
        'memory_kind': kind.wire,
        'title': title,
        'summary': summary,
        'scope': (input['scope'] as String?)?.trim().isNotEmpty == true
            ? (input['scope'] as String).trim()
            : '*',
        'entities': entities,
        'memory_payload': memoryPayload,
        'importance': importance,
        // This becomes true only after confirmation. The value represents
        // provenance, not model confidence.
        'confidence': 0.95,
        if (validFrom != null)
          'valid_from': validFrom.toUtc().toIso8601String(),
        if (validUntil != null)
          'valid_until': validUntil.toUtc().toIso8601String(),
      });
    }

    final candidateId = _uuid.v4();
    final proposalId = _uuid.v4();
    payload['candidate_id'] = candidateId;
    final now = DateTime.now().toUtc();
    final store = await ctx.ref.read(memoryCandidateStoreProvider.future);
    await store.insert(
      MemoryChangeCandidate(
        id: candidateId,
        proposalId: proposalId,
        ownerUserId: session.userId,
        operation: operation,
        status: MemoryCandidateStatus.pending,
        targetMemoryId: targetMemoryId.isEmpty ? null : targetMemoryId,
        payload: Map<String, Object?>.unmodifiable(payload),
        createdAt: now,
        updatedAt: now,
      ),
    );

    final summaryZh = switch (operation) {
      MemoryCandidateOperation.create => '建议记住：“${payload['title']}” — $reason',
      MemoryCandidateOperation.supersede =>
        '建议更新长期记忆“$targetTitle”为“${payload['title']}” — $reason',
      MemoryCandidateOperation.forget => '建议忘记长期记忆“$targetTitle” — $reason',
    };
    return readyPlan(
      proposalId: proposalId,
      kind: 'memory_change',
      summaryZh: summaryZh,
      payload: payload,
      note: '这是待确认的长期记忆候选；确认前不会写入或删除正式 Memory。',
    );
  }
}

DateTime? _optionalDate(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim())?.toUtc();
}
