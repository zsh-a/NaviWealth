/// Unit-tests for [LlmCaptureClassifier].
///
/// Drives the classifier with a [FakeDeviceLlmClient] that returns
/// scripted Anthropic-shaped `content` blocks. Covers the happy path,
/// JSON-in-prose extraction, confidence guards, and the silent
/// degradation to heuristic on every failure mode.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_client.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/llm_stream_event.dart';
import 'package:naviwealth/features/knowledge/data/capture_kind.dart';
import 'package:naviwealth/features/knowledge/data/llm_capture_classifier.dart';

class _FakeConfig implements DeviceLlmConfig {
  const _FakeConfig();
  @override
  String get model => 'test-model';
}

/// Returns one of several scripted outcomes per call. The
/// [LlmCaptureClassifier] only uses [complete] — [streamMessages] is
/// implemented as an unreachable stub.
class FakeDeviceLlmClient implements DeviceLlmClient {
  FakeDeviceLlmClient({required this.behavior});

  final FakeBehavior behavior;
  int calls = 0;

  @override
  DeviceLlmConfig get config => const _FakeConfig();

  @override
  Stream<LlmStreamEvent> streamMessages(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<AnthropicCompletion> complete(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    return behavior.run();
  }
}

abstract class FakeBehavior {
  Future<AnthropicCompletion> run();
}

class _ReturnsText extends FakeBehavior {
  _ReturnsText(this.text);
  final String text;
  @override
  Future<AnthropicCompletion> run() async => AnthropicCompletion(
    content: <Object?>[
      <String, Object?>{'type': 'text', 'text': text},
    ],
  );
}

class _Throws extends FakeBehavior {
  _Throws(this.error);
  final Object error;
  @override
  Future<AnthropicCompletion> run() async => throw error;
}

class _Hangs extends FakeBehavior {
  @override
  Future<AnthropicCompletion> run() {
    // Never completes — drives the classifier into its timeout branch.
    return Completer<AnthropicCompletion>().future;
  }
}

void main() {
  group('LlmCaptureClassifier — happy path', () {
    test('parses a clean routine JSON envelope', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{
  "kind": "routine",
  "confidence": 0.92,
  "reason_zh": "用户表达「港卡每 6 个月活跃一次」的周期事项",
  "statement": "港卡做一次活跃交易",
  "interval_days": 180,
  "scope": "finance/cards/hk"
}'''),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '港卡每 6 个月做一次活跃交易，否则会休眠。');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 180);
      expect(r.scope, 'finance/cards/hk');
      expect(r.statement, '港卡做一次活跃交易');
      expect(r.confidence, closeTo(0.92, 0.0001));
      expect(fake.calls, 1);
    });

    test('parses a decision envelope (no interval_days)', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{
  "kind": "decision",
  "confidence": 0.78,
  "reason_zh": "用户在权衡两个对冲方案",
  "statement": "升级到 QQQ + BOXX 动态对冲 vs 保持现状",
  "scope": "*"
}'''),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '我应该升级到 QQQ + BOXX 动态对冲，还是保持现状?');
      expect(r.kind, CaptureKind.decision);
      expect(r.statement, '升级到 QQQ + BOXX 动态对冲 vs 保持现状');
      expect(r.intervalDays, isNull);
      expect(r.scope, isNull, reason: 'scope == "*" maps to null');
    });

    test('strips Markdown code fence wrapper', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('''
Sure, here's the classification:

```json
{
  "kind": "concept",
  "confidence": 0.81,
  "reason_zh": "短小命名定义",
  "statement": "edge-first"
}
```
'''),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: 'edge-first: prefer fast iteration.');
      expect(r.kind, CaptureKind.concept);
      expect(r.statement, 'edge-first');
    });

    test('clamps routine interval into valid range', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{"kind":"routine","confidence":0.9,"reason_zh":"x","interval_days":99999}'''),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '每天提醒');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 3650);
    });
  });

  group('LlmCaptureClassifier — guardrails', () {
    test('low-confidence upgrade is downgraded to Note', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{"kind":"routine","confidence":0.3,"reason_zh":"勉强像","interval_days":180}'''),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '可能要定期 ...');
      expect(r.kind, CaptureKind.note);
      expect(r.reasonZh, contains('置信度'));
    });

    test('low-confidence downgrade still carries polish fields', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{"kind":"routine","confidence":0.3,"reason_zh":"勉强像","interval_days":180,
 "polished_title":"清理后的标题","polished_body":"清理后的正文"}'''),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '可能要定期 xxx');
      expect(r.kind, CaptureKind.note);
      expect(r.hasPolish, isTrue);
      expect(r.polishedTitle, '清理后的标题');
      expect(r.polishedBody, '清理后的正文');
    });
  });

  group('LlmCaptureClassifier — polish', () {
    test('routine envelope carries polished title + body', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{
  "kind": "routine",
  "confidence": 0.9,
  "reason_zh": "周期事项",
  "statement": "港卡定期活跃",
  "interval_days": 180,
  "polished_title": "港卡定期活跃",
  "polished_body": "港卡每 6 个月做一次活跃交易，否则会休眠。"
}'''),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: 'gangka每6個月活躍。。。');
      expect(r.kind, CaptureKind.routine);
      expect(r.hasPolish, isTrue);
      expect(r.polishedTitle, '港卡定期活跃');
      expect(r.polishedBody, contains('港卡每 6 个月'));
      expect(r.hasSuggestion, isTrue);
    });

    test('kind=note + polish only — hasSuggestion is true', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{
  "kind": "note",
  "confidence": 0.4,
  "reason_zh": "无明显结构,只润色",
  "polished_title": "清晨想到的一句",
  "polished_body": "清理后的正文。"
}'''),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '清晨..想到的，一句，  乱七八糟');
      expect(r.kind, CaptureKind.note);
      expect(r.isUpgrade, isFalse);
      expect(r.hasPolish, isTrue);
      expect(r.hasSuggestion, isTrue, reason: 'polish alone triggers UI');
    });

    test('empty polish strings normalize to null (no suggestion)', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{"kind":"note","confidence":0.5,"reason_zh":"无结构",
 "polished_title":"","polished_body":"   "}'''),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '今天读了一本书');
      expect(r.kind, CaptureKind.note);
      expect(r.hasPolish, isFalse);
      expect(r.hasSuggestion, isFalse);
    });

    test('missing polish fields → null, no false positive', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText(
          '{"kind":"note","confidence":0.5,"reason_zh":"无结构"}',
        ),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '今天读了一本书');
      expect(r.polishedTitle, isNull);
      expect(r.polishedBody, isNull);
      expect(r.hasSuggestion, isFalse);
    });
  });

  group('LlmCaptureClassifier — fallback to heuristic', () {
    test('malformed JSON → heuristic kicks in', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('I think this is a routine, but no JSON.'),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '港卡每 6 个月活跃一次');
      // Heuristic catches "每 6 个月" + 港卡 scope.
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 180);
      expect(r.scope, 'finance/cards');
    });

    test('client throws → heuristic kicks in', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _Throws(
          const LlmRequestException(statusCode: 500, message: 'boom'),
        ),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '每周做一次 review');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 7);
    });

    test('timeout → heuristic kicks in', () async {
      final fake = FakeDeviceLlmClient(behavior: _Hangs());
      final c = LlmCaptureClassifier(
        client: fake,
        requestTimeout: const Duration(milliseconds: 50),
      );
      final r = await c.classify(text: '港卡每 6 个月活跃一次');
      expect(r.kind, CaptureKind.routine);
    });

    test('JSON missing "kind" → heuristic kicks in', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText('{"confidence":0.9,"reason_zh":"x"}'),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '每年报税');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 365);
    });

    test('unknown kind string → heuristic kicks in', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText(
          '{"kind":"strategy","confidence":0.9,"reason_zh":"x"}',
        ),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '每年做一次体检');
      expect(r.kind, CaptureKind.routine, reason: '"strategy" 非法,heuristic 接管');
      expect(r.scope, 'health');
    });

    test('empty text never invokes the client', () async {
      final fake = FakeDeviceLlmClient(
        behavior: _ReturnsText(
          '{"kind":"routine","confidence":1,"reason_zh":"x"}',
        ),
      );
      final c = LlmCaptureClassifier(client: fake);
      final r = await c.classify(text: '   ');
      expect(r.kind, CaptureKind.note);
      expect(fake.calls, 0);
    });
  });
}
