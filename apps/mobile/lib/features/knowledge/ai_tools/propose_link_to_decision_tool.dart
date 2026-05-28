/// `propose_link_to_decision` — InboxTriageAgent write tool
/// (`docs/knowledgeos-domain.md` §4 + §7).
///
/// Suggests existing Decision(s) that the inbox Note should be linked
/// to (e.g. "this looks like supporting evidence for your covered-call
/// decision"). The Review tab accept path applies the link as a tag
/// of the form `decision:<id>` so we don't need a new schema column.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/inbox_triage_repository.dart';
import '../data/providers.dart';
import '_inbox_triage_support.dart';

class ProposeLinkToDecisionTool implements DeviceTool {
  const ProposeLinkToDecisionTool();

  @override
  String get name => 'propose_link_to_decision';

  @override
  String get description =>
      '把某条 Inbox Note 关联到一条或多条已有 Decision。'
      '**不会**直接写关联(§4 反目标 + §7 InboxTriageAgent 工程约束)— 返回 proposal envelope 并写入 '
      'knowledge_inbox_triage 给 Review tab "AI 建议" 卡片渲染。'
      '用户 ✓ 时在 note.tags 中添加 "decision:<id>" 标签(轻量软链,不改 schema);✗ 时下次不再为该 note 提议关联。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'note_id': {'type': 'string'},
      'related_decision_ids': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'reason': {
        'type': 'string',
        'description': '一句中文说明为什么挂到这些 decision。会显示给用户。',
      },
    },
    'required': <String>[
      'note_id',
      'related_decision_ids',
      'reason',
    ],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final noteId = (input['note_id'] as String?)?.trim() ?? '';
    final reason = (input['reason'] as String?)?.trim() ?? '';
    final rawIds = input['related_decision_ids'];
    final ids = rawIds is List
        ? rawIds
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    if (ids.isEmpty || reason.isEmpty) {
      return <String, Object?>{
        'error': 'related_decision_ids 不能为空; reason 必填。',
        'code': 'bad_request',
      };
    }

    final loaded = await loadOwnedNote(ctx, noteId);
    if (loaded.error != null) return loaded.error;
    final note = loaded.note!;

    // Verify the decisions belong to the same owner — cross-account
    // leakage is the only failure mode here that justifies a bad_request.
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final valid = <String>[];
    final invalid = <String>[];
    for (final id in ids) {
      final d = await repo.findDecision(id);
      if (d != null && d.sync.ownerUserId == ownerUserId) {
        valid.add(id);
      } else {
        invalid.add(id);
      }
    }
    if (valid.isEmpty) {
      return <String, Object?>{
        'error':
            '提供的 decision id 都找不到或不属于当前用户:${invalid.join(", ")}',
        'code': 'bad_request',
      };
    }

    final summary =
        '把 "${_preview(note.title, note.bodyMd)}" 关联到 ${valid.length} 条 decision — $reason';
    final payload = <String, Object?>{
      'note_id': noteId,
      'related_decision_ids': valid,
      'reason': reason,
      if (invalid.isNotEmpty) 'skipped_ids': invalid,
    };

    await persistEnvelope(
      ctx: ctx,
      noteId: noteId,
      ownerUserId: note.sync.ownerUserId,
      kind: InboxProposalKind.linkToDecision,
      summaryZh: summary,
      payload: payload,
    );

    return proposalEnvelope(
      kind: 'knowledge_inbox_link_to_decision',
      summaryZh: summary,
      payload: payload,
    );
  }

  static String _preview(String title, String body) {
    if (title.isNotEmpty) return title;
    if (body.isEmpty) return '(untitled)';
    return body.length > 30 ? '${body.substring(0, 30)}…' : body;
  }
}
