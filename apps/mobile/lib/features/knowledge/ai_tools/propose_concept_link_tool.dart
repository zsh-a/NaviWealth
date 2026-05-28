/// `propose_concept_link` — KnowledgeOS device write tool
/// (`docs/knowledgeos-domain.md` §4).
///
/// **Write semantics**: returns a proposal envelope; the user must
/// confirm in the UI before the link lands. Matches the cross-domain
/// `propose_*` pattern — see
/// `lib/features/finance/ai_tools/_shared/propose/proposal_plan.dart`
/// (per the northstar 行为契约 / ai-architecture.md).
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';

class ProposeConceptLinkTool implements DeviceTool {
  const ProposeConceptLinkTool();

  @override
  String get name => 'propose_concept_link';

  @override
  String get description =>
      '建议两个 KnowledgeOS Concept 之间建立关联(双向加入对方 related_concept_ids)。'
      '**不会**直接写入 — 返回 proposal envelope,等用户在 UI 确认。'
      '输入需要双方 id + relation 标签 + reason。'
      '若 from_concept_id 或 to_concept_id 不存在,返回 bad_request。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'from_concept_id': {'type': 'string'},
      'to_concept_id': {'type': 'string'},
      'relation': {
        'type': 'string',
        'description': '自然语言关系标签,例如 "is_a" / "related" / "contradicts" / "supports"。',
      },
      'reason': {
        'type': 'string',
        'description': '一句中文说明为什么建联。会显示给用户。',
      },
    },
    'required': <String>[
      'from_concept_id',
      'to_concept_id',
      'relation',
      'reason',
    ],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final fromId = (input['from_concept_id'] as String?)?.trim() ?? '';
    final toId = (input['to_concept_id'] as String?)?.trim() ?? '';
    final relation = (input['relation'] as String?)?.trim() ?? '';
    final reason = (input['reason'] as String?)?.trim() ?? '';

    if (fromId.isEmpty || toId.isEmpty || relation.isEmpty || reason.isEmpty) {
      return <String, Object?>{
        'error':
            'from_concept_id / to_concept_id / relation / reason 全部必填。',
        'code': 'bad_request',
      };
    }
    if (fromId == toId) {
      return <String, Object?>{
        'error': '不能为同一个 concept 建立到自己的关联。',
        'code': 'bad_request',
      };
    }

    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final from = await repo.findConcept(fromId);
    final to = await repo.findConcept(toId);
    if (from == null || from.sync.ownerUserId != ownerUserId) {
      return <String, Object?>{
        'error': 'from_concept_id $fromId 不存在',
        'code': 'bad_request',
      };
    }
    if (to == null || to.sync.ownerUserId != ownerUserId) {
      return <String, Object?>{
        'error': 'to_concept_id $toId 不存在',
        'code': 'bad_request',
      };
    }

    return <String, Object?>{
      'proposal_id': kKnowledgeUuid.v4(),
      'kind': 'knowledge_concept_link',
      'status': 'ready',
      'summary_zh':
          '在 "${from.name}" 和 "${to.name}" 之间建立 "$relation" 关联 — $reason',
      'payload': <String, Object?>{
        'from_concept_id': fromId,
        'from_concept_name': from.name,
        'to_concept_id': toId,
        'to_concept_name': to.name,
        'relation': relation,
        'reason': reason,
      },
      'warnings': const <String>[],
      'missing': const <String>[],
      'candidates': null,
      'note':
          '前端必须显示 summary_zh 给用户确认；只有用户明确点确认后才走 Repository。',
    };
  }
}
