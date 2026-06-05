/// `queue_inbox_tags` — InboxTriageAgent write tool
/// (`docs/knowledgeos-domain.md` §4 + §7).
///
/// Suggests tag list + optional `project_tag` for a Note. Returns a
/// ProposalEnvelope; the Review tab applies tags via
/// `KnowledgeRepository.upsertNote` when the user accepts.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../data/inbox_triage_repository.dart';
import '_inbox_triage_support.dart';

class QueueInboxTagsTool implements DeviceTool {
  const QueueInboxTagsTool();

  @override
  String get name => 'queue_inbox_tags';

  @override
  String get description =>
      '为 Inbox 中的某条 Note 提议 tag 列表(以及可选 project_tag)。'
      '**不会**直接改 note(§4 反目标 + §7 InboxTriageAgent 工程约束)— 返回 proposal envelope 并写入 '
      'knowledge_inbox_triage 给 Review tab "AI 建议" 卡片渲染。'
      '用户 ✓ 时合并进 note.tags / 设置 project_tag;✗ 时下次不再为该 note 提议 tags。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'note_id': {'type': 'string'},
      'tags': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '建议的 tag 列表(小写、短词;例如 "fire", "options")。',
      },
      'project_tag': {
        'type': 'string',
        'description': '可选 — 关联到某个 project 的短标识(例如 "house-search")。',
      },
      'reason': {'type': 'string', 'description': '一句中文说明为什么这些 tag 合适。会显示给用户。'},
    },
    'required': <String>['note_id', 'tags', 'reason'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final noteId = (input['note_id'] as String?)?.trim() ?? '';
    final rawTags = input['tags'];
    final projectTag = (input['project_tag'] as String?)?.trim();
    final reason = (input['reason'] as String?)?.trim() ?? '';

    final tags = rawTags is List
        ? rawTags
              .whereType<String>()
              .map((t) => t.trim().toLowerCase())
              .where((t) => t.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    if (tags.isEmpty || reason.isEmpty) {
      return badRequest('tags 不能为空; reason 必填。');
    }

    final loaded = await loadOwnedNote(ctx, noteId);
    if (loaded.error != null) return loaded.error;
    final note = loaded.note!;

    final summary = projectTag != null && projectTag.isNotEmpty
        ? '为 "${notePreview(note.title, note.bodyMd)}" 建议 tags ${tags.join("/")},project=$projectTag — $reason'
        : '为 "${notePreview(note.title, note.bodyMd)}" 建议 tags ${tags.join("/")} — $reason';

    final payload = <String, Object?>{
      'note_id': noteId,
      'tags': tags,
      if (projectTag != null && projectTag.isNotEmpty)
        'project_tag': projectTag,
      'reason': reason,
    };

    await persistEnvelope(
      ctx: ctx,
      noteId: noteId,
      ownerUserId: note.sync.ownerUserId,
      kind: InboxProposalKind.tags,
      summaryZh: summary,
      payload: payload,
    );

    return proposalEnvelope(
      kind: 'knowledge_inbox_tags',
      summaryZh: summary,
      payload: payload,
    );
  }
}
