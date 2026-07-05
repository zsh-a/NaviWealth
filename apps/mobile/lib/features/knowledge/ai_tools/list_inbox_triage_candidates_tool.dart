/// `list_inbox_triage_candidates` — KnowledgeOS device tool
/// (`docs/domains/knowledgeos-domain.md` §5 + §7).
///
/// Returns recent notes that do not yet have a row in the local-only
/// `knowledge_inbox_triage` side table. This is the read half of
/// `InboxTriageAgent`; proposal persistence still happens in Dart after the
/// classifier decides what to emit.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';

class ListInboxTriageCandidatesTool implements DeviceTool {
  const ListInboxTriageCandidatesTool();

  @override
  String get name => 'list_inbox_triage_candidates';

  @override
  String get description =>
      '列出尚未进入 knowledge_inbox_triage side-table 的最近 KnowledgeOS notes。'
      '用途: InboxTriageAgent 读取待分诊 note; 只读,不写 proposal。'
      '返回 notes: id / title / body_md / tags / project_tag / created_at。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50, 'default': 10},
      'scan_limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 500,
        'default': 200,
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final triage = await ctx.ref.read(inboxTriageRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 50)
        : 10;
    final scanLimit = (input['scan_limit'] is num)
        ? (input['scan_limit'] as num).toInt().clamp(1, 500)
        : 200;

    final notes = await repo.listNotes(
      ownerUserId: ownerUserId,
      limit: scanLimit,
    );
    final triagedIds = await triage.triagedNoteIds(ownerUserId: ownerUserId);
    final candidates = notes
        .where((note) => !triagedIds.contains(note.id))
        .take(limit)
        .map(_noteRecord)
        .toList(growable: false);

    return <String, Object?>{'notes': candidates};
  }

  static Map<String, Object?> _noteRecord(KnowledgeNote note) {
    return <String, Object?>{
      'id': note.id,
      'title': note.title,
      'body_md': note.bodyMd,
      'excerpt': knowledgeExcerpt(note.bodyMd),
      'tags': note.tags,
      'project_tag': note.projectTag,
      'created_at': note.createdAt.toUtc().toIso8601String(),
    };
  }
}
