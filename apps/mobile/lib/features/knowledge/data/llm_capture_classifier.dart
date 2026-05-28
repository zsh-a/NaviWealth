/// LLM-driven capture classifier (`docs/knowledgeos-domain.md` §4 + §14).
///
/// Same shape as [LlmBriefingSynthesizer] from HealthOS: wrap the user's
/// configured [DeviceLlmClient], compose a tight system prompt that
/// emits structured JSON, parse, validate, return. On *any* failure
/// (no network, provider error, timeout, malformed JSON, schema
/// mismatch) it degrades silently to the heuristic baseline so the
/// Capture sheet never blocks on AI.
///
/// Why JSON-in-text instead of `tools` + forced tool_use:
/// `AnthropicRequest` exposes a `tools` array but not `tool_choice`
/// (the wire was ported from a backend that never forced calls). Plain
/// JSON output is reliable enough for a 7-kind taxonomy and avoids
/// growing the shared wire surface for one consumer.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/ai/runtime/device/anthropic/anthropic_client.dart';
import '../../../core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'capture_classifier.dart';
import 'capture_kind.dart';

class LlmCaptureClassifier implements CaptureClassifier {
  const LlmCaptureClassifier({
    required this.client,
    this.fallback = const HeuristicCaptureClassifier(),
    this.maxTokens = 400,
    this.requestTimeout = const Duration(seconds: 8),
  });

  final DeviceLlmClient client;
  final CaptureClassifier fallback;
  final int maxTokens;
  final Duration requestTimeout;

  /// System prompt is kept short and load-bearing — the LLM gets the
  /// 7-kind taxonomy + a strict JSON schema, plus the "if uncertain
  /// pick note" rule that keeps false-positive upgrades rare.
  static const String _system =
      '你是 NaviWealth KnowledgeOS 的捕获分类器。给定用户刚输入的一段自由文本,'
      '把它分类到这 7 类对象之一,并抽取结构化字段:\n'
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
      '仅输出一个 JSON 对象,**不要任何额外文字 / Markdown / 代码栅栏**。schema:\n'
      '{\n'
      '  "kind": "note|routine|decision|principle|assumption|concept|experiment",\n'
      '  "confidence": 数字 0..1,\n'
      '  "reason_zh": "一句中文说明",\n'
      '  "statement": "提取出的一句话陈述,短",\n'
      '  "interval_days": 整数 1..3650 (routine 时必填),\n'
      '  "scope": "可选自由 tag,例如 finance/cards/hk 或 health 或 *"\n'
      '}';

  @override
  Future<CaptureClassification> classify({required String text}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return fallback.classify(text: text);

    try {
      final request = AnthropicRequest(
        model: client.config.model,
        maxTokens: maxTokens,
        system: _system,
        messages: <AnthropicChatMessage>[
          AnthropicChatMessage.text('user', trimmed),
        ],
        stream: false,
      );
      final completion = await client
          .complete(request, cancelToken: CancelToken())
          .timeout(requestTimeout);
      final body = _extractText(completion);
      if (body == null) return fallback.classify(text: text);

      final json = _extractJsonObject(body);
      if (json == null) return fallback.classify(text: text);

      final parsed = _parseClassification(json);
      if (parsed == null) return fallback.classify(text: text);

      return parsed;
    } on Object {
      return fallback.classify(text: text);
    }
  }

  static String? _extractText(AnthropicCompletion completion) {
    for (final block in completion.content) {
      if (block is! Map) continue;
      if (block['type'] == 'text' && block['text'] is String) {
        return block['text'] as String;
      }
    }
    return null;
  }

  /// Pull the first balanced `{...}` substring out of the model's
  /// reply. Claude occasionally wraps JSON in prose / code fences
  /// despite the prompt; this strips both forms.
  static Map<String, Object?>? _extractJsonObject(String text) {
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

  static CaptureClassification? _parseClassification(
    Map<String, Object?> json,
  ) {
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

    // Enforce the prompt's "≥0.6 confidence to upgrade" rule defensively
    // — protects the user even if the model bypasses it.
    if (kind != CaptureKind.note && confidence < 0.6) {
      return CaptureClassification(
        kind: CaptureKind.note,
        confidence: confidence,
        reasonZh: 'LLM 给出 $kindRaw 但置信度仅 ${confidence.toStringAsFixed(2)},保留为 Note',
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

    final statementRaw = (json['statement'] as String?)?.trim();
    final scopeRaw = (json['scope'] as String?)?.trim();

    return CaptureClassification(
      kind: kind,
      confidence: confidence.clamp(0.0, 1.0),
      reasonZh: reason,
      intervalDays: intervalDays,
      statement: (statementRaw == null || statementRaw.isEmpty)
          ? null
          : statementRaw,
      scope:
          (scopeRaw == null || scopeRaw.isEmpty || scopeRaw == '*')
              ? null
              : scopeRaw,
    );
  }

  static double? _coerceDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _coerceInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
