/// Unit-tests for [FrbCaptureClassifier].
///
/// Drives the classifier with a fake FRB LLM bridge returning scripted profile
/// completion content. Covers the happy path, JSON-in-prose extraction,
/// confidence guards, polish handling, and fallback behavior.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/data/capture_kind.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_llm_client.dart';
import 'package:naviwealth/features/knowledge/data/llm_capture_classifier.dart';

void main() {
  group('FrbCaptureClassifier', () {
    test(
      'parses a clean routine JSON envelope from profile completion',
      () async {
        final bridge = _FakeLlmBridge(
          responseText: '''
{
  "kind": "routine",
  "confidence": 0.92,
  "reason_zh": "用户表达周期事项",
  "statement": "港卡做一次活跃交易",
  "interval_days": 180,
  "scope": "finance/cards/hk"
}''',
        );
        final c = FrbCaptureClassifier(llmClient: bridge);

        final r = await c.classify(text: '港卡每 6 个月做一次活跃交易，否则会休眠。');

        expect(bridge.calls, 1);
        expect(bridge.lastMessages.first['role'], 'system');
        expect(bridge.lastMessages.last['role'], 'user');
        expect(bridge.lastMetadata['surface'], 'knowledge_capture');
        expect(r.kind, CaptureKind.routine);
        expect(r.intervalDays, 180);
        expect(r.scope, 'finance/cards/hk');
        expect(r.statement, '港卡做一次活跃交易');
      },
    );

    test(
      'low-confidence upgrade is downgraded while preserving polish',
      () async {
        final bridge = _FakeLlmBridge(
          responseText: '''
{"kind":"routine","confidence":0.3,"reason_zh":"勉强像","interval_days":180,
 "polished_title":"清理后的标题","polished_body":"清理后的正文"}''',
        );
        final c = FrbCaptureClassifier(llmClient: bridge);

        final r = await c.classify(text: '可能要定期 xxx');

        expect(r.kind, CaptureKind.note);
        expect(r.reasonZh, contains('置信度'));
        expect(r.hasPolish, isTrue);
        expect(r.polishedTitle, '清理后的标题');
        expect(r.polishedBody, '清理后的正文');
      },
    );

    test('parses decision envelopes and wildcard scope', () async {
      final bridge = _FakeLlmBridge(
        responseText: '''
{
  "kind": "decision",
  "confidence": 0.78,
  "reason_zh": "用户在权衡两个对冲方案",
  "statement": "升级到 QQQ + BOXX 动态对冲 vs 保持现状",
  "decision_options": ["升级到 QQQ + BOXX 动态对冲", "保持现状"],
  "scope": "*"
}''',
      );
      final c = FrbCaptureClassifier(llmClient: bridge);

      final r = await c.classify(text: '我应该升级到 QQQ + BOXX 动态对冲，还是保持现状?');

      expect(r.kind, CaptureKind.decision);
      expect(r.statement, '升级到 QQQ + BOXX 动态对冲 vs 保持现状');
      expect(r.decisionOptions, ['升级到 QQQ + BOXX 动态对冲', '保持现状']);
      expect(r.intervalDays, isNull);
      expect(r.scope, isNull, reason: 'scope == "*" maps to null');
    });

    test('strips Markdown code fence wrappers', () async {
      final bridge = _FakeLlmBridge(
        responseText: '''
Sure, here's the classification:

```json
{
  "kind": "concept",
  "confidence": 0.81,
  "reason_zh": "短小命名定义",
  "statement": "edge-first"
}
```
''',
      );
      final c = FrbCaptureClassifier(llmClient: bridge);

      final r = await c.classify(text: 'edge-first: prefer fast iteration.');

      expect(r.kind, CaptureKind.concept);
      expect(r.statement, 'edge-first');
    });

    test('clamps routine intervals into valid range', () async {
      final bridge = _FakeLlmBridge(
        responseText:
            '{"kind":"routine","confidence":0.9,"reason_zh":"x","interval_days":99999}',
      );
      final c = FrbCaptureClassifier(llmClient: bridge);

      final r = await c.classify(text: '每天提醒');

      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 3650);
    });

    test('note with polish only still counts as a suggestion', () async {
      final bridge = _FakeLlmBridge(
        responseText: '''
{
  "kind": "note",
  "confidence": 0.4,
  "reason_zh": "无明显结构,只润色",
  "polished_title": "清晨想到的一句",
  "polished_body": "清理后的正文。"
}''',
      );
      final c = FrbCaptureClassifier(llmClient: bridge);

      final r = await c.classify(text: '清晨..想到的，一句，  乱七八糟');

      expect(r.kind, CaptureKind.note);
      expect(r.isUpgrade, isFalse);
      expect(r.hasPolish, isTrue);
      expect(r.hasSuggestion, isTrue);
    });

    test('keeps a complete structured Markdown organization draft', () async {
      final bridge = _FakeLlmBridge(
        responseText: '''
{
  "kind": "note",
  "confidence": 0.8,
  "reason_zh": "整理标题和阅读层级",
  "polished_title": "现金管理方案比较",
  "polished_body": "## 核心判断\\n\\n优先保证流动性。\\n\\n## 方案比较\\n\\n| 方案 | 特点 |\\n| --- | --- |\\n| A | 灵活 |\\n| B | 稳定 |"
}''',
      );
      final c = FrbCaptureClassifier(llmClient: bridge);

      final r = await c.classify(
        text: '{"original_title":"","original_body_md":"A 灵活，B 稳定，优先保证流动性"}',
      );

      expect(r.polishedTitle, '现金管理方案比较');
      expect(r.polishedBody, contains('## 核心判断'));
      expect(r.polishedBody, contains('| 方案 | 特点 |'));
      expect(
        bridge.lastMessages.first['content'],
        contains('polished_body 是完整正文'),
      );
      expect(bridge.lastTemperature, 0.2);
    });

    test('empty polish strings normalize to null', () async {
      final bridge = _FakeLlmBridge(
        responseText: '''
{"kind":"note","confidence":0.5,"reason_zh":"无结构",
 "polished_title":"","polished_body":"   "}''',
      );
      final c = FrbCaptureClassifier(llmClient: bridge);

      final r = await c.classify(text: '今天读了一本书');

      expect(r.kind, CaptureKind.note);
      expect(r.hasPolish, isFalse);
      expect(r.hasSuggestion, isFalse);
    });

    test('malformed JSON falls back to heuristic', () async {
      final bridge = _FakeLlmBridge(
        responseText: 'I think this is a routine, but no JSON.',
      );
      final c = FrbCaptureClassifier(llmClient: bridge);

      final r = await c.classify(text: '港卡每 6 个月活跃一次');

      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 180);
      expect(r.scope, 'finance/cards');
    });

    test('JSON missing kind falls back to heuristic', () async {
      final bridge = _FakeLlmBridge(
        responseText: '{"confidence":0.9,"reason_zh":"x"}',
      );
      final c = FrbCaptureClassifier(llmClient: bridge);

      final r = await c.classify(text: '每年报税');

      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 365);
    });

    test('unknown kind string falls back to heuristic', () async {
      final bridge = _FakeLlmBridge(
        responseText: '{"kind":"strategy","confidence":0.9,"reason_zh":"x"}',
      );
      final c = FrbCaptureClassifier(llmClient: bridge);

      final r = await c.classify(text: '每年做一次体检');

      expect(r.kind, CaptureKind.routine);
      expect(r.scope, 'health');
    });

    test('empty text never invokes the FRB bridge', () async {
      final bridge = _FakeLlmBridge(
        responseText: '{"kind":"routine","confidence":1,"reason_zh":"x"}',
      );
      final c = FrbCaptureClassifier(llmClient: bridge);

      final r = await c.classify(text: '   ');

      expect(r.kind, CaptureKind.note);
      expect(bridge.calls, 0);
    });

    test('falls back to heuristic when FRB completion throws', () async {
      final c = FrbCaptureClassifier(
        llmClient: _FakeLlmBridge(error: StateError('native unavailable')),
      );

      final r = await c.classify(text: '每周做一次 review');

      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 7);
    });
  });
}

class _FakeLlmBridge implements KnowledgeLlmProfileClient {
  _FakeLlmBridge({this.responseText, this.error});

  final String? responseText;
  final Object? error;
  var calls = 0;
  List<Map<String, Object?>> lastMessages = const <Map<String, Object?>>[];
  Map<String, Object?> lastMetadata = const <String, Object?>{};
  double? lastTemperature;

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    calls += 1;
    lastMessages = messages;
    lastMetadata = metadata;
    lastTemperature = temperature;
    final e = error;
    if (e != null) throw e;
    return <String, Object?>{
      'provider': 'mock',
      'model': 'test-model',
      'content': responseText ?? '',
    };
  }
}
