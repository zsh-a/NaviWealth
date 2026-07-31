/// FRB-backed capture classifier (`docs/domains/knowledgeos-domain.md` §4 + §14).
///
/// Sends the capture prompt through the FRB profile-backed LLM bridge. On *any*
/// failure (no bridge, provider error, timeout, malformed JSON, schema
/// mismatch) it degrades silently to the heuristic baseline so the Capture
/// sheet never blocks on AI.
///
/// Plain JSON output is reliable enough for a 7-kind taxonomy and keeps this to
/// one profile completion.
library;

import 'dart:async';
import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../domain/knowledge_text.dart';
import 'capture_classifier.dart';
import 'capture_kind.dart';
import 'knowledge_llm_client.dart';

/// Log channel used by every checkpoint in this file. Grep the talker
/// history for `[capture-llm]` to trace one classify() call end-to-end.
const String _kLogTag = '[capture-llm]';

const String _kCaptureSystemPrompt =
    '你是 NaviWealth KnowledgeOS 的捕获分类器 + 文本润色助手。'
    '给定用户刚输入的一段自由文本,做两件事:\n'
    '\n'
    '【一】分类到这 7 类之一,并抽取结构化字段:\n'
    '- note: 普通笔记 (默认 fallback,没有明显结构)\n'
    '- routine: 周期性提醒 ("每 N 天/周/月/年" / "定期续期 / 活跃 / 缴费" /'
    ' "需要定期 ...")\n'
    '- decision: 权衡选项的决策 (含 "应该 / vs / 对比 / 选项 A vs B" 等)\n'
    '- principle: 长期世界观原语 (不可证伪 / 价值观陈述)\n'
    '- assumption: 可证伪的信念 + 隐含置信度\n'
    '- concept: 概念定义 (短小的命名解释)\n'
    '- experiment: 验证假设的实验 (含 hypothesis / 方法 / 指标)\n'
    '\n'
    '不确定就选 note;不要为了"显得有用"硬升级。confidence < 0.6 也优先 note。\n'
    '\n'
    '【二】润色:产出更清晰的 polished_title 和 polished_body。规则:\n'
    '- 含义必须与原文完全一致,不增不减事实,**不要补充任何用户没写的细节**\n'
    '- 修正拼写 / 标点 / 错别字 / 重复字 / 中英文混排留意空格\n'
    '- 可以把口语化短句改写为简洁陈述,但不要变成"文章风格"\n'
    '- 若用户原文已经清晰干净,就把对应字段输出为 null,不要硬润色\n'
    '- 用户原文是中文就输出中文,英文就输出英文 (跟随原语言)\n'
    '- polished_title 用一个短标题(≤ 20 字符), polished_body 是完整正文(Markdown 可用)\n'
    '- 当内容包含明确的步骤、流程、决策路径时,在 polished_body 中使用 '
    '```flow fenced block 渲染为流程图:\n'
    '  ```flow\n'
    '  step: 步骤一\n'
    '  step: 步骤二\n'
    '  decision: 关键判断?\n'
    '    yes: 路径 A\n'
    '    no: 路径 B\n'
    '  step: 最终步骤\n'
    '  ```\n'
    '  节点类型: step(步骤), decision(判断,带 yes/no 分支), info(备注/提示)\n'
    '  不是所有内容都适合流程图 — 仅当有清晰的线性步骤或决策分支时使用;其余用普通 Markdown\n'
    '\n'
    '仅输出一个 JSON 对象,**不要任何额外文字 / Markdown / 代码栅栏**。schema:\n'
    '{\n'
    '  "kind": "note|routine|decision|principle|assumption|concept|experiment",\n'
    '  "confidence": 数字 0..1,\n'
    '  "reason_zh": "一句中文说明",\n'
    '  "statement": "提取出的一句话陈述,短",\n'
    '  "interval_days": 整数 1..3650 (routine 时必填),\n'
    '  "scope": "可选自由 tag,例如 finance/cards/hk 或 health 或 *",\n'
    '  "decision_options": ["决策选项A", "决策选项B"] (decision 时至少两项),\n'
    '  "expected_outcome": "可选预期结果",\n'
    '  "assumption_confidence": 数字 0..1 (assumption 时必填),\n'
    '  "experiment_metrics": ["成功指标"] (experiment 时至少一项),\n'
    '  "experiment_method": "验证方法" (experiment 时必填),\n'
    '  "polished_title": "润色后的标题或 null",\n'
    '  "polished_body": "润色后的正文或 null"\n'
    '}';

String _preview(String s) {
  final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return knowledgeExcerpt(flat, max: kKnowledgeHeadlineExcerptMaxChars);
}

Map<String, Object?>? _extractJsonObject(String text) {
  final start = text.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escape = false;
  for (var i = start; i < text.length; i++) {
    final c = text[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (inString) {
      if (c == r'\') {
        escape = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
      continue;
    }
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        final slice = text.substring(start, i + 1);
        try {
          final decoded = jsonDecode(slice);
          if (decoded is Map) {
            return decoded.map((k, v) => MapEntry(k.toString(), v));
          }
          return null;
        } on FormatException {
          return null;
        }
      }
    }
  }
  return null;
}

String? _nullIfEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

double? _coerceDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _coerceInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

class FrbCaptureClassifier implements CaptureClassifier {
  const FrbCaptureClassifier({
    required this.llmClient,
    this.fallback = const HeuristicCaptureClassifier(),
    this.maxTokens = 8192,
    this.requestTimeout = const Duration(seconds: 45),
    this.logger,
  });

  final KnowledgeLlmProfileClient llmClient;
  final CaptureClassifier fallback;
  final int maxTokens;
  final Duration requestTimeout;
  final AppLogger? logger;

  @override
  Future<CaptureClassification> classify({required String text}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      logger?.d('$_kLogTag empty input, deferring to fallback');
      return fallback.classify(text: text);
    }

    final preview = _preview(trimmed);
    logger?.i(
      '$_kLogTag frb start text_len=${trimmed.length} preview="$preview"',
    );

    final stopwatch = Stopwatch()..start();
    try {
      final response = await llmClient
          .completeProfile(
            messages: <Map<String, Object?>>[
              const <String, Object?>{
                'role': 'system',
                'content': _kCaptureSystemPrompt,
              },
              <String, Object?>{'role': 'user', 'content': trimmed},
            ],
            maxOutputTokens: maxTokens,
            metadata: const <String, Object?>{
              'surface': 'knowledge_capture',
              'agent_id': 'knowledge_capture',
            },
          )
          .timeout(requestTimeout);
      logger?.i(
        '$_kLogTag frb response ${stopwatch.elapsedMilliseconds}ms '
        'provider=${response['provider'] ?? "(unknown)"}',
      );

      final body = response['content'];
      if (body is! String || body.trim().isEmpty) {
        logger?.w('$_kLogTag FRB response missing content, falling back');
        return fallback.classify(text: text);
      }

      final json = _extractJsonObject(body);
      if (json == null) {
        logger?.w(
          '$_kLogTag FRB JSON extract failed, falling back. '
          'body preview="${_preview(body)}"',
        );
        return fallback.classify(text: text);
      }

      final parsed = _parseCaptureClassification(json);
      if (parsed == null) {
        logger?.w(
          '$_kLogTag FRB JSON parse rejected, falling back. '
          'keys=${json.keys.toList()}',
        );
        return fallback.classify(text: text);
      }

      logger?.i(
        '$_kLogTag frb parsed kind=${parsed.kind.wire} '
        'confidence=${parsed.confidence.toStringAsFixed(2)} '
        'isUpgrade=${parsed.isUpgrade} hasPolish=${parsed.hasPolish} '
        'interval=${parsed.intervalDays} scope=${parsed.scope}',
      );
      return parsed;
    } on Object catch (err, st) {
      logger?.w(
        '$_kLogTag frb exception after ${stopwatch.elapsedMilliseconds}ms '
        '(${err.runtimeType}: $err), falling back to heuristic',
        error: err,
        stackTrace: st,
      );
      return fallback.classify(text: text);
    }
  }
}

CaptureClassification? _parseCaptureClassification(Map<String, Object?> json) {
  final kindRaw = (json['kind'] as String?)?.trim();
  if (kindRaw == null || kindRaw.isEmpty) return null;
  final kind = CaptureKind.parse(kindRaw);
  // If the LLM returned a string outside the enum, [CaptureKind.parse]
  // falls back to `note` — but we should *not* treat that as a "note
  // signal" because the model intended something else. Distinguish
  // explicit `note` from unknown by comparing strings.
  if (kind == CaptureKind.note && kindRaw != 'note') return null;

  final confidence = _coerceDouble(json['confidence']) ?? 0.0;
  final reason = (json['reason_zh'] as String?)?.trim() ?? '';
  if (reason.isEmpty) return null;

  // Polish fields parsed up front because they're orthogonal to the
  // upgrade decision — even a low-confidence downgrade still carries
  // the rewrite through so the user can accept just the polish.
  final polishedTitle = _nullIfEmpty(
    (json['polished_title'] as String?)?.trim(),
  );
  final polishedBody = _nullIfEmpty((json['polished_body'] as String?)?.trim());

  // Enforce the prompt's "≥0.6 confidence to upgrade" rule defensively
  // — protects the user even if the model bypasses it.
  if (kind != CaptureKind.note && confidence < 0.6) {
    return CaptureClassification(
      kind: CaptureKind.note,
      confidence: confidence,
      reasonZh:
          'LLM 给出 $kindRaw 但置信度仅 ${confidence.toStringAsFixed(2)},保留为 Note',
      polishedTitle: polishedTitle,
      polishedBody: polishedBody,
    );
  }

  int? intervalDays = _coerceInt(json['interval_days']);
  if (kind == CaptureKind.routine) {
    // Routine without an interval is unusable for RoutineDueAgent;
    // require it (LLM should set it; fall back to 180 if it didn't).
    intervalDays ??= 180;
    if (intervalDays < 1) intervalDays = 1;
    if (intervalDays > 3650) intervalDays = 3650;
  }

  final statementRaw = _nullIfEmpty((json['statement'] as String?)?.trim());
  final decisionOptions = _stringList(json['decision_options']);
  final expectedOutcome = _nullIfEmpty(
    (json['expected_outcome'] as String?)?.trim(),
  );
  final assumptionConfidence = _coerceDouble(
    json['assumption_confidence'],
  )?.clamp(0.0, 1.0);
  final experimentMetrics = _stringList(json['experiment_metrics']);
  final experimentMethod = _nullIfEmpty(
    (json['experiment_method'] as String?)?.trim(),
  );
  if (kind == CaptureKind.decision && decisionOptions.length < 2 ||
      kind == CaptureKind.assumption && assumptionConfidence == null ||
      kind == CaptureKind.experiment &&
          (experimentMetrics.isEmpty || experimentMethod == null)) {
    return null;
  }
  final scopeRawTrimmed = (json['scope'] as String?)?.trim();
  final scope =
      (scopeRawTrimmed == null ||
          scopeRawTrimmed.isEmpty ||
          scopeRawTrimmed == '*')
      ? null
      : scopeRawTrimmed;

  return CaptureClassification(
    kind: kind,
    confidence: confidence.clamp(0.0, 1.0),
    reasonZh: reason,
    intervalDays: intervalDays,
    statement: statementRaw,
    scope: scope,
    decisionOptions: decisionOptions,
    expectedOutcome: expectedOutcome,
    assumptionConfidence: assumptionConfidence,
    experimentMetrics: experimentMetrics,
    experimentMethod: experimentMethod,
    polishedTitle: polishedTitle,
    polishedBody: polishedBody,
  );
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .take(8)
      .toList(growable: false);
}
