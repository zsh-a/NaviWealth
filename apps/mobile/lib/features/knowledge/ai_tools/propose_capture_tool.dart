/// `propose_capture` — unified capture-classification device tool
/// (`docs/knowledgeos-domain.md` §4 + §14.2 P1).
///
/// Given a freeform text the user just captured (or an existing note's
/// body), classify it into one of 7 KnowledgeOS kinds and return a
/// proposal envelope. Heuristic-only MVP (shared with the in-sheet
/// `CaptureClassifier`) — LLM-augmented classification is the same
/// follow-up tracked for `InboxTriageAgent`. The envelope payload is
/// shaped so the front-end can apply it without re-classifying.
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
      '把一段用户刚输入的自由文本分类为 KnowledgeOS 的 7 类对象之一'
      '(note / routine / decision / principle / assumption / concept / experiment),'
      '并抽取结构化字段。**不会**直接写库,返回 proposal envelope,'
      '前端显示 summary_zh 让用户一键确认升级。'
      '适用:Capture sheet 保存后 / 用户问「这条该归到哪里」/「这是不是一个 Routine」。'
      'kind == note 时表示无需升级,envelope.status == "no_upgrade"。'
      '内部走 captureClassifierProvider:有 LLM profile 时调 LLM(全 7 类抽取),'
      '否则走纯 Dart heuristic(目前稳定识别 routine,其余兜底 note)。'
      '任意失败(网络 / 解析)都退守 heuristic,前端永远拿到合法 envelope。';

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

    if (classification.kind == CaptureKind.note && !classification.hasPolish) {
      return <String, Object?>{
        'proposal_id': kKnowledgeUuid.v4(),
        'kind': 'capture_no_upgrade',
        'status': 'no_upgrade',
        'summary_zh': '保留为 Note —— ${classification.reasonZh}',
        'payload': <String, Object?>{
          'detected_kind': CaptureKind.note.wire,
          'confidence': classification.confidence,
        },
        'note': '没有强信号升级为其它类型;前端无需追问,Note 已是合理表达。',
      };
    }

    final payload = <String, Object?>{
      'detected_kind': classification.kind.wire,
      'confidence': classification.confidence,
      'reason': classification.reasonZh,
      'source_text': text,
      if (noteId != null && noteId.isNotEmpty) 'note_id': noteId,
      if (classification.statement != null)
        'statement': classification.statement,
      if (classification.intervalDays != null)
        'interval_days': classification.intervalDays,
      if (classification.scope != null) 'scope': classification.scope,
      if (classification.polishedTitle != null)
        'polished_title': classification.polishedTitle,
      if (classification.polishedBody != null)
        'polished_body': classification.polishedBody,
    };

    final polishHint = classification.hasPolish ? ' [含 AI 润色]' : '';
    final summary = switch (classification.kind) {
      CaptureKind.routine =>
        '检出周期事项:"${classification.statement ?? text}",'
            '建议升级为 Routine(每 ${classification.intervalDays} 天) — '
            '${classification.reasonZh}$polishHint',
      CaptureKind.note when classification.hasPolish =>
        '保留为 Note,AI 提议润色文本 — ${classification.reasonZh}',
      _ =>
        '检出 ${classification.kind.wire},建议升级 — ${classification.reasonZh}$polishHint',
    };

    return proposalEnvelope(
      kind: 'capture_upgrade',
      summaryZh: summary,
      payload: payload,
      note:
          '前端在 CaptureSheet 内嵌升级卡片,用户 ✓ 才落地;✗ 保留 Note。'
          '若 note_id 已传,apply 流程负责删 Note + 写目标行(transactional)。',
    );
  }
}
