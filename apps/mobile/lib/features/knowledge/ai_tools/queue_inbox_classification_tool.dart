/// `queue_inbox_classification` — InboxTriageAgent write tool
/// (`docs/domains/knowledgeos-domain.md` §4 + §7).
///
/// Suggests how an inbox note should be re-categorised: stay as a
/// plain note, upgrade to a Decision draft, or extract as a Concept.
/// Returns a ProposalEnvelope — the user accepts in the Review tab.
/// **Never writes** to `knowledge_notes` directly.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../data/inbox_triage_repository.dart';
import '_inbox_triage_support.dart';

const Set<String> _kClassifications = <String>{'decision', 'concept'};

class QueueInboxClassificationTool implements DeviceTool {
  const QueueInboxClassificationTool();

  @override
  String get name => 'queue_inbox_classification';

  @override
  String get description =>
      '建议将某条 Inbox Note 升级为哪类一等对象(decision / concept)。'
      '**不会**直接改 note.body_md(§4 反目标 + §7 InboxTriageAgent 工程约束)— 返回 proposal envelope,'
      '同时写入 knowledge_inbox_triage 让 Review tab "AI 建议" 卡片可见。'
      '用户在 Review tab ✓ 时才创建对应的一等 Knowledge 对象;✗ 时下次 InboxTriageAgent 不再为该 note 重提此 kind。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'note_id': {'type': 'string'},
      'kind': {
        'type': 'string',
        'enum': _kClassifications.toList(growable: false),
      },
      'confidence': {
        'type': 'number',
        'description': '0..1 — agent 对该分类的把握程度,影响 UI 排序。',
        'minimum': 0,
        'maximum': 1,
      },
      'reason': {'type': 'string', 'description': '一句中文说明为什么这么分类。会显示给用户。'},
      'decision_options': {
        'type': 'array',
        'items': {'type': 'string'},
        'minItems': 2,
        'description': 'kind=decision 时必填，至少两个真实选项。',
      },
      'expected_outcome': {
        'type': 'string',
        'description': 'kind=decision 时可选的预期结果。',
      },
    },
    'required': <String>['note_id', 'kind', 'reason'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final noteId = (input['note_id'] as String?)?.trim() ?? '';
    final kind = (input['kind'] as String?)?.trim() ?? '';
    final reason = (input['reason'] as String?)?.trim() ?? '';
    final confidence = (input['confidence'] as num?)?.toDouble() ?? 0.6;
    final decisionOptions = input['decision_options'] is List
        ? (input['decision_options'] as List)
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    final expectedOutcome = (input['expected_outcome'] as String?)?.trim();

    if (!_kClassifications.contains(kind) || reason.isEmpty) {
      return badRequest('kind 必须是 decision / concept; reason 必填。');
    }
    if (kind == 'decision' && decisionOptions.length < 2) {
      return badRequest('decision 分类必须提供至少两个 decision_options。');
    }

    final loaded = await loadOwnedNote(ctx, noteId);
    if (loaded.error != null) return loaded.error;
    final note = loaded.note!;

    final summary =
        '建议将 "${notePreview(note.title, note.bodyMd)}" 归为 $kind — $reason';
    final payload = <String, Object?>{
      'note_id': noteId,
      'kind': kind,
      'confidence': confidence.clamp(0.0, 1.0),
      'reason': reason,
      if (kind == 'decision') 'decision_options': decisionOptions,
      if (expectedOutcome != null && expectedOutcome.isNotEmpty)
        'expected_outcome': expectedOutcome,
    };

    await persistEnvelope(
      ctx: ctx,
      noteId: noteId,
      ownerUserId: note.sync.ownerUserId,
      kind: InboxProposalKind.classification,
      summaryZh: summary,
      payload: payload,
    );

    return proposalEnvelope(
      kind: 'knowledge_inbox_classification',
      summaryZh: summary,
      payload: payload,
    );
  }
}
