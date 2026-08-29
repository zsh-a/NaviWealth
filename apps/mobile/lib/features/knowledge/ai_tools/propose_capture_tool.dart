/// `propose_capture` — unified capture-classification device tool
/// (`docs/domains/knowledgeos-domain.md` §4 + §14.2 P1).
///
/// Given a freeform text the user just captured (or an existing note's
/// body), decide whether it should stay a Note or become a Decision, and
/// return a proposal envelope. The richer legacy classifier remains an
/// internal signal source, but its ontology is not exposed to the user.
///
/// Write semantics: **never** writes the target row directly. Front-end
/// applies after user one-tap confirms.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../data/capture_kind.dart';
import '../data/providers.dart';
import '_tool_support.dart';

class ProposeCaptureTool implements DeviceTool {
  const ProposeCaptureTool();

  @override
  String get name => 'propose_capture';

  @override
  String get description =>
      '判断一段用户输入应保留为 KnowledgeOS Note，还是升级为 Decision。'
      '**不会**直接写库；只有 Decision 或文本润色会返回待确认 proposal。'
      '旧版对象分类仅作为内部信号，不要求用户理解或选择底层类型。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': '用户刚输入的自由文本(整段)。'},
      'note_id': {
        'type': 'string',
        'description':
            '可选 — 若文本已落 KnowledgeNote,把 id 也传进来,前端 apply 时可一次性删除/升级。',
      },
    },
    'required': <String>['text'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final text = (input['text'] as String?)?.trim() ?? '';
    final noteId = (input['note_id'] as String?)?.trim();

    if (text.isEmpty) {
      return badRequest('text 必填且不能为空。');
    }

    final classifier = ctx.ref.read(captureClassifierProvider);
    final classification = await classifier.classify(text: text);
    final visibleKind = classification.kind == CaptureKind.decision
        ? CaptureKind.decision
        : CaptureKind.note;

    if (visibleKind == CaptureKind.note && !classification.hasPolish) {
      return noUpgradeEnvelope(
        summaryZh: '保留为 Note —— ${classification.reasonZh}',
        payload: <String, Object?>{
          'detected_kind': CaptureKind.note.wire,
          'confidence': classification.confidence,
        },
        note: '没有强信号升级为其它类型;前端无需追问,Note 已是合理表达。',
      );
    }

    final payload = <String, Object?>{
      'detected_kind': visibleKind.wire,
      'confidence': classification.confidence,
      'reason': classification.reasonZh,
      'source_text': text,
      if (noteId != null && noteId.isNotEmpty) 'note_id': noteId,
      if (classification.scope != null) 'scope': classification.scope,
      if (classification.polishedTitle != null)
        'polished_title': classification.polishedTitle,
      if (classification.polishedBody != null)
        'polished_body': classification.polishedBody,
    };

    final polishHint = classification.hasPolish ? ' [含 AI 润色]' : '';
    final summary = switch (visibleKind) {
      CaptureKind.decision =>
        '建议升级为 Decision — ${classification.reasonZh}$polishHint',
      CaptureKind.note when classification.hasPolish =>
        '保留为 Note,AI 提议润色文本 — ${classification.reasonZh}',
      _ => '保留为 Note — ${classification.reasonZh}',
    };

    return proposalEnvelope(
      kind: 'capture_upgrade',
      summaryZh: summary,
      payload: payload,
      note:
          '用户确认后才升级为 Decision 或应用 Note 润色；取消则保留原 Note。'
          '若 note_id 已传,apply 流程负责删 Note + 写目标行(transactional)。',
    );
  }
}
