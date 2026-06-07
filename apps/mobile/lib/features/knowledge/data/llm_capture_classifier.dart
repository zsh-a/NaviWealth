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
import '../../../core/logging/app_logger.dart';
import '../domain/knowledge_text.dart';
import 'capture_classifier.dart';
import 'capture_kind.dart';

/// Log channel used by every checkpoint in this file. Grep the talker
/// history for `[capture-llm]` to trace one classify() call end-to-end.
const String _kLogTag = '[capture-llm]';

class LlmCaptureClassifier implements CaptureClassifier {
  const LlmCaptureClassifier({
    required this.client,
    this.fallback = const HeuristicCaptureClassifier(),
    // Generous budget: extended-thinking models (mimo, Claude-thinking)
    // burn most of the budget on reasoning before the JSON answer. A
    // tight cap (the old 2000) truncated them mid-thought → only a
    // thinking block, no usable JSON → forced heuristic fallback. Don't
    // starve the model.
    this.maxTokens = 8192,
    // Long enough for a slow thinking model to actually finish; the
    // heuristic fallback still covers the timeout case.
    this.requestTimeout = const Duration(seconds: 45),
    this.logger,
  });

  final DeviceLlmClient client;
  final CaptureClassifier fallback;
  final int maxTokens;
  final Duration requestTimeout;

  /// Optional structured logger — null means silent (test default).
  /// Production wiring injects [loggerProvider]'s instance so the run
  /// shows up in the Talker history alongside Dio + agent logs.
  final AppLogger? logger;

  /// System prompt is kept short and load-bearing — the LLM gets the
  /// 7-kind taxonomy + a strict JSON schema, plus the "if uncertain
  /// pick note" rule that keeps false-positive upgrades rare.
  ///
  /// `polished_title` / `polished_body` ride on the same call so we
  /// don't pay a second round-trip for polish. The model is asked to
  /// preserve meaning (no advice, no invented facts) and to leave the
  /// field null when the user's wording is already clear.
  static const String _system =
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
      '\n'
      '仅输出一个 JSON 对象,**不要任何额外文字 / Markdown / 代码栅栏**。schema:\n'
      '{\n'
      '  "kind": "note|routine|decision|principle|assumption|concept|experiment",\n'
      '  "confidence": 数字 0..1,\n'
      '  "reason_zh": "一句中文说明",\n'
      '  "statement": "提取出的一句话陈述,短",\n'
      '  "interval_days": 整数 1..3650 (routine 时必填),\n'
      '  "scope": "可选自由 tag,例如 finance/cards/hk 或 health 或 *",\n'
      '  "polished_title": "润色后的标题或 null",\n'
      '  "polished_body": "润色后的正文或 null"\n'
      '}';

  @override
  Future<CaptureClassification> classify({required String text}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      logger?.d('$_kLogTag empty input, deferring to fallback');
      return fallback.classify(text: text);
    }

    final preview = _preview(trimmed);
    logger?.i(
      '$_kLogTag start model=${client.config.model} '
      'text_len=${trimmed.length} preview="$preview"',
    );

    final stopwatch = Stopwatch()..start();
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
      final elapsed = stopwatch.elapsedMilliseconds;
      logger?.i(
        '$_kLogTag response ${elapsed}ms '
        'content_blocks=${completion.content.length} '
        'stop_reason=${completion.stopReason ?? "(null)"}',
      );

      final body = _extractText(completion);
      if (body == null) {
        // Detect the "thinking-only" failure mode: extended-thinking
        // models (Claude with thinking enabled, mimo, etc.) burn the
        // token budget on internal reasoning and never reach the text
        // block. Make this case loud so the user knows to raise their
        // provider's token budget or switch to a non-thinking model.
        final blockTypes = completion.content
            .whereType<Map<Object?, Object?>>()
            .map((b) => b['type']?.toString() ?? '?')
            .toList(growable: false);
        final thinkingOnly =
            blockTypes.isNotEmpty && blockTypes.every((t) => t == 'thinking');
        if (thinkingOnly && completion.stopReason == 'max_tokens') {
          logger?.w(
            '$_kLogTag response had only thinking blocks (stop_reason=max_tokens, '
            'maxTokens=$maxTokens) — provider model burned all tokens on extended '
            'reasoning. Raise maxTokens or pick a non-thinking model. '
            'Falling back to heuristic.',
          );
        } else {
          logger?.w(
            '$_kLogTag no text block in response (block_types=$blockTypes, '
            'stop_reason=${completion.stopReason ?? "(null)"}), falling back',
          );
        }
        return fallback.classify(text: text);
      }
      logger?.d('$_kLogTag text body len=${body.length}');

      final json = _extractJsonObject(body);
      if (json == null) {
        logger?.w(
          '$_kLogTag JSON extract failed, falling back. body preview="${_preview(body)}"',
        );
        return fallback.classify(text: text);
      }

      final parsed = _parseClassification(json);
      if (parsed == null) {
        logger?.w(
          '$_kLogTag JSON parse rejected (missing kind/reason/unknown kind), '
          'falling back. keys=${json.keys.toList()}',
        );
        return fallback.classify(text: text);
      }

      logger?.i(
        '$_kLogTag parsed kind=${parsed.kind.wire} '
        'confidence=${parsed.confidence.toStringAsFixed(2)} '
        'isUpgrade=${parsed.isUpgrade} hasPolish=${parsed.hasPolish} '
        'interval=${parsed.intervalDays} scope=${parsed.scope}',
      );
      return parsed;
    } on Object catch (err, st) {
      final elapsed = stopwatch.elapsedMilliseconds;
      logger?.w(
        '$_kLogTag exception after ${elapsed}ms (${err.runtimeType}: $err), '
        'falling back to heuristic',
        error: err,
        stackTrace: st,
      );
      return fallback.classify(text: text);
    }
  }

  /// 80-char text preview for log lines. Strips newlines so the log
  /// stays one row per call.
  static String _preview(String s) {
    final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return knowledgeExcerpt(flat, max: kKnowledgeHeadlineExcerptMaxChars);
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

    // Polish fields parsed up front because they're orthogonal to the
    // upgrade decision — even a low-confidence downgrade still carries
    // the rewrite through so the user can accept just the polish.
    final polishedTitle = _nullIfEmpty(
      (json['polished_title'] as String?)?.trim(),
    );
    final polishedBody = _nullIfEmpty(
      (json['polished_body'] as String?)?.trim(),
    );

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
      polishedTitle: polishedTitle,
      polishedBody: polishedBody,
    );
  }

  static String? _nullIfEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

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
