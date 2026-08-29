/// `propose_merge` creates a user-confirmed Note or Decision merge.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '_tool_support.dart';

class ProposeMergeTool implements DeviceTool {
  const ProposeMergeTool();

  @override
  String get name => 'propose_merge';

  @override
  String get description => '建议合并重复的 Note 或 Decision。只生成待确认方案，不直接写入。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'entity_type': <String, Object?>{
        'type': 'string',
        'enum': <String>['note', 'decision'],
      },
      'primary_id': <String, Object?>{'type': 'string'},
      'duplicate_ids': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
        'minItems': 1,
      },
      'reason': <String, Object?>{'type': 'string'},
    },
    'required': <String>[
      'entity_type',
      'primary_id',
      'duplicate_ids',
      'reason',
    ],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final kind = (input['entity_type'] as String?)?.trim() ?? '';
    final primaryId = (input['primary_id'] as String?)?.trim() ?? '';
    final reason = (input['reason'] as String?)?.trim() ?? '';
    final duplicates = input['duplicate_ids'] is List
        ? (input['duplicate_ids'] as List<Object?>)
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty && value != primaryId)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    if (!const <String>{'note', 'decision'}.contains(kind)) {
      return badRequest('entity_type 只支持 note / decision。');
    }
    if (primaryId.isEmpty || duplicates.isEmpty || reason.isEmpty) {
      return badRequest('primary_id、duplicate_ids、reason 均为必填。');
    }

    final repository = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    Future<String?> label(String id) async => switch (kind) {
      'note' => (await repository.findNote(
        ownerUserId: ownerUserId,
        id: id,
      ))?.title,
      'decision' => (await repository.findDecision(
        ownerUserId: ownerUserId,
        id: id,
      ))?.question,
      _ => null,
    };
    final kept = await label(primaryId);
    final removed = <String>[];
    final missing = <String>[];
    if (kept == null) missing.add(primaryId);
    for (final id in duplicates) {
      final value = await label(id);
      if (value == null) {
        missing.add(id);
      } else {
        removed.add(value);
      }
    }
    if (missing.isNotEmpty) {
      return notFound('以下条目不存在：${missing.join(', ')}', missing);
    }
    return proposalEnvelope(
      kind: 'knowledge_merge',
      summaryZh: '合并 ${duplicates.length} 条重复内容到「$kept」— $reason',
      payload: <String, Object?>{
        'entity_type': kind,
        'primary_id': primaryId,
        'duplicate_ids': duplicates,
        'reason': reason,
        'diff': <String, Object?>{'kept': kept, 'removed': removed},
      },
      note: '用户确认后执行软合并，可撤销。',
    );
  }
}
