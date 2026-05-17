import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/features/ai_chat/ui/ai_transparency_badge.dart';

void main() {
  group('formatAiTraceBadge', () {
    test('hybrid + no disclosure + 1 tool + sub-second', () {
      final trace = _trace(
        backend: Backend.hybrid,
        usedRawLedger: false,
        toolCount: 1,
        durationMs: 850,
      );
      expect(
        formatAiTraceBadge(trace),
        '本地数据 + 云端推理 · 未上传原始交易明细 · 1 个工具 · 850ms',
      );
    });

    test('device-only path with no tools', () {
      final trace = _trace(
        backend: Backend.device,
        usedRawLedger: false,
        toolCount: 0,
        durationMs: 80,
      );
      expect(
        formatAiTraceBadge(trace),
        '全部本地处理 · 未上传原始交易明细 · 80ms',
      );
    });

    test('discloses ledger detail when consent was granted', () {
      final trace = _trace(
        backend: Backend.hybrid,
        usedRawLedger: true,
        toolCount: 2,
        durationMs: 2400,
      );
      expect(
        formatAiTraceBadge(trace),
        '本地数据 + 云端推理 · 已授权使用明细数据 · 2 个工具 · 2.4s',
      );
    });

    test('rounds long durations to whole seconds', () {
      final trace = _trace(
        backend: Backend.cloud,
        usedRawLedger: false,
        toolCount: 0,
        durationMs: 13_400,
      );
      expect(
        formatAiTraceBadge(trace),
        '仅云端推理 · 未上传原始交易明细 · 13s',
      );
    });

    test('surfaces staleReadModels count when non-zero', () {
      final trace = _trace(
        backend: Backend.hybrid,
        usedRawLedger: false,
        toolCount: 2,
        durationMs: 1200,
        staleReadModels: 1,
      );
      expect(
        formatAiTraceBadge(trace),
        '本地数据 + 云端推理 · 未上传原始交易明细 · 2 个工具 · 1 项数据滞后 · 1.2s',
      );
    });
  });
}

AiTrace _trace({
  required Backend backend,
  required bool usedRawLedger,
  required int toolCount,
  required int durationMs,
  int staleReadModels = 0,
}) => AiTrace(
  requestId: 't',
  startedAtIso: '2026-05-10T10:00:00.000Z',
  intent: const IntentHint(
    capability: Capability.analyze,
    risk: RiskLevel.suggest,
  ),
  backend: backend,
  budgetTier: BudgetTier.standard,
  routingReason: 'test',
  usedCloud: backend != Backend.device,
  usedRawLedger: usedRawLedger,
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
  staleReadModelNames: Set<String>.from(
    List<String>.generate(staleReadModels, (i) => 'rm_$i'),
  ),
);
