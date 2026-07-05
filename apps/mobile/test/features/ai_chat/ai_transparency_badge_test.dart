import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/features/ai_chat/ui/ai_transparency_badge.dart';

void main() {
  group('formatAiTraceBadge', () {
    test('hybrid + 1 tool + sub-second', () {
      final trace = _trace(
        backend: Backend.hybrid,
        toolCount: 1,
        durationMs: 850,
      );
      expect(formatAiTraceBadge(trace), '本地数据 + 端侧推理 · 1 个工具 · 850ms');
    });

    test('device-only path with no tools', () {
      final trace = _trace(
        backend: Backend.device,
        toolCount: 0,
        durationMs: 80,
      );
      expect(formatAiTraceBadge(trace), '全部本地处理 · 80ms');
    });

    test('rounds long durations to whole seconds', () {
      final trace = _trace(
        backend: Backend.cloud,
        toolCount: 0,
        durationMs: 13_400,
      );
      expect(formatAiTraceBadge(trace), '端侧模型推理 · 13s');
    });

    test('FRB Vision ingest path discloses provider direct routing', () {
      final trace = _trace(
        backend: Backend.device,
        toolCount: 0,
        durationMs: 1300,
        routingReason: kFrbVisionIngestRoutingReason,
      );
      expect(formatAiTraceBadge(trace), '端侧直连模型 · 请求与数据未经我方服务器 · 1.3s');
    });

    test('legacy device Vision direct path keeps provider disclosure', () {
      final trace = _trace(
        backend: Backend.device,
        toolCount: 0,
        durationMs: 1300,
        routingReason: kDeviceVisionDirectRoutingReason,
      );
      expect(formatAiTraceBadge(trace), contains('未经我方服务器'));
    });
  });
}

AiTrace _trace({
  required Backend backend,
  required int toolCount,
  required int durationMs,
  String routingReason = 'test',
}) => AiTrace(
  requestId: 't',
  startedAtIso: '2026-05-10T10:00:00.000Z',
  intent: const IntentHint(
    capability: Capability.analyze,
    risk: RiskLevel.suggest,
  ),
  backend: backend,
  budgetTier: BudgetTier.standard,
  routingReason: routingReason,
  totalDurationMs: durationMs,
  spans: List<AiSpan>.generate(
    toolCount,
    (i) => AiSpan(
      id: 'tool:$i',
      parentId: 'r1',
      kind: AiSpanKind.tool,
      name: 'tool:tool_$i',
      startOffsetMs: i * 10,
      durationMs: 10,
    ),
  ),
);
