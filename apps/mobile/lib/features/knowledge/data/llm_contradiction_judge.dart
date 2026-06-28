/// LLM-backed contradiction judge (`docs/domains/knowledgeos-domain.md` §7 +
/// §14.2 "ContradictionAgent cosine + LLM judge 路径").
///
/// Same shape as [LlmInboxTriageClassifier]: wrap the user's configured
/// [DeviceLlmClient], compose one tight system prompt that emits a single
/// structured JSON object, parse + validate, and map onto a
/// [ContradictionVerdict]. **≤ 1 LLM round-trip per candidate pair.** The
/// agent's cosine pre-filter bounds the candidate set (top-K per
/// principle) so the total call count stays cheap.
///
/// On *any* failure — no LLM profile (the provider hands a heuristic
/// instance instead, so this class is only constructed with a client),
/// network / provider error, timeout, malformed JSON, schema mismatch,
/// or confidence below 0.6 — it degrades silently to
/// [HeuristicContradictionJudge]. It never throws and never blocks the
/// agent tick.
///
/// JSON-in-text (not forced tool_use) for the same reason as the inbox
/// classifier: the shared wire exposes `tools` but not `tool_choice`, and
/// plain JSON is reliable enough here.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/ai/runtime/device/anthropic/anthropic_client.dart';
import '../../../core/ai/runtime/device/anthropic/anthropic_wire.dart';
import '../../../core/logging/app_logger.dart';
import 'contradiction_judge.dart';

/// Grep the Talker history for `[contradiction-llm]` to trace one
/// judge() call end-to-end.
const String _kLogTag = '[contradiction-llm]';

/// Same gate the inbox classifier uses — a verdict the model is less than
/// 60% sure about is dropped (no flag), which is the core
/// false-positive-suppression win over the old marker heuristic.
const double _kMinConfidence = 0.6;

class LlmContradictionJudge implements ContradictionJudge {
  const LlmContradictionJudge({
    required this.client,
    this.fallback = const HeuristicContradictionJudge(),
    // Generous budget so extended-thinking models can finish (matching
    // LlmInboxTriageClassifier).
    this.maxTokens = 4096,
    // Per-pair budget. The heuristic fallback covers the timeout case so
    // a slow pair never stalls the tick.
    this.requestTimeout = const Duration(seconds: 8),
    this.logger,
  });

  final DeviceLlmClient client;
  final ContradictionJudge fallback;
  final int maxTokens;
  final Duration requestTimeout;

  /// Optional structured logger — null means silent (test default).
  final AppLogger? logger;

  static const String _system =
      '你是 NaviWealth KnowledgeOS 的"价值观一致性"审查员。给定用户的一条 '
      'active Principle(原则)和一段最近的内容(某个 Decision 或 Note 的标题+摘要),'
      '判断这段内容是否**真正违背**了该原则(价值观漂移 / 事实冲突),'
      '而不仅仅是顺带提到、复述、或完全无关。\n'
      '\n'
      '严格区分:\n'
      '- 真冲突:内容里的主张 / 决定与原则方向相反(例如原则"长期持有",内容"打算频繁波段交易")。\n'
      '- 仅提及 / 复述 / 引用原则本身 → 不是冲突。\n'
      '- 与原则无关 → 不是冲突。\n'
      '\n'
      '宁缺毋滥:只有确有把握是真冲突时才判 true,否则一律 false。'
      'confidence 低于 0.6 的本系统会自动忽略。\n'
      '\n'
      '仅输出一个 JSON 对象,**不要任何额外文字 / Markdown / 代码栅栏**。schema:\n'
      '{\n'
      '  "is_contradiction": true/false,\n'
      '  "confidence": 0..1 的数字,\n'
      '  "reason_zh": "一句中文,说明为什么算/不算冲突"\n'
      '}';

  @override
  Future<ContradictionVerdict> judge({
    required String principleStatement,
    required String memoryText,
  }) async {
    final principle = principleStatement.trim();
    final memory = memoryText.trim();
    if (principle.isEmpty || memory.isEmpty) {
      return fallback.judge(
        principleStatement: principleStatement,
        memoryText: memoryText,
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final userMsg = _buildUserMessage(principle, memory);
      final request = AnthropicRequest(
        model: client.config.model,
        maxTokens: maxTokens,
        system: _system,
        messages: <AnthropicChatMessage>[
          AnthropicChatMessage.text('user', userMsg),
        ],
        stream: false,
      );
      final completion = await client
          .complete(request, cancelToken: CancelToken())
          .timeout(requestTimeout);
      logger?.d(
        '$_kLogTag response ${stopwatch.elapsedMilliseconds}ms '
        'blocks=${completion.content.length} '
        'stop=${completion.stopReason ?? "(null)"}',
      );

      final body = _extractText(completion);
      if (body == null) {
        logger?.w('$_kLogTag no text block, falling back to heuristic');
        return _fallback(principleStatement, memoryText);
      }
      final json = _extractJsonObject(body);
      if (json == null) {
        logger?.w('$_kLogTag JSON extract failed, falling back');
        return _fallback(principleStatement, memoryText);
      }

      final verdict = _parseVerdict(json);
      // A well-formed "not a contradiction" verdict is a valid LLM
      // answer — do NOT fall back, that would re-introduce the marker
      // noise the model deliberately suppressed.
      logger?.i(
        '$_kLogTag verdict isContradiction=${verdict.isContradiction} '
        'confidence=${verdict.confidence}',
      );
      return verdict;
    } on Object catch (err, st) {
      logger?.w(
        '$_kLogTag exception after ${stopwatch.elapsedMilliseconds}ms '
        '(${err.runtimeType}: $err), falling back to heuristic',
        error: err,
        stackTrace: st,
      );
      return _fallback(principleStatement, memoryText);
    }
  }

  Future<ContradictionVerdict> _fallback(
    String principleStatement,
    String memoryText,
  ) {
    return fallback.judge(
      principleStatement: principleStatement,
      memoryText: memoryText,
    );
  }

  static String _buildUserMessage(String principle, String memory) {
    final buf = StringBuffer()
      ..writeln('## Principle(原则)')
      ..writeln(principle)
      ..writeln()
      ..writeln('## 最近内容(Decision / Note 摘要)')
      ..writeln(memory);
    return buf.toString();
  }

  ContradictionVerdict _parseVerdict(Map<String, Object?> json) {
    final isContradiction = json['is_contradiction'] == true;
    final confidence = (_coerceDouble(json['confidence']) ?? 0.0).clamp(
      0.0,
      1.0,
    );
    final reason = (json['reason_zh'] as String?)?.trim() ?? '';
    if (!isContradiction || confidence < _kMinConfidence || reason.isEmpty) {
      // Below the gate (or a clean "no") → no flag.
      return const ContradictionVerdict.none();
    }
    return ContradictionVerdict(
      isContradiction: true,
      confidence: confidence,
      reasonZh: reason,
    );
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

  /// Pull the first balanced `{...}` substring out of the reply (handles
  /// prose / code-fence wrapping despite the prompt). Copied verbatim
  /// from [LlmInboxTriageClassifier].
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

  static double? _coerceDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
