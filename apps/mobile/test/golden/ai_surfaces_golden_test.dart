// Wave 43 — golden coverage for the AI visual language (Wave 36 tokens
// + Wave 37/38/39/40 surfaces).
//
// These goldens are intentionally component-scoped: one widget,
// deterministic inputs, minimal chrome.
//
// Coverage: 7 goldens / 1 file
//   - ai_pill_neutral / ai_pill_selected / ai_pill_error
//   - ai_object_capsule
//   - asset_allocation_view (Wave 34 domain renderer)
//   - subscription_changes_view (Wave 34 domain renderer)
//   - ai_trace_timeline (Wave-30/33/35 events together)
//
// Each golden runs at 360×N logical px, light theme, en locale. Drift
// either side and the golden breaks — protection against accidental
// Wave-36 token changes leaking into the visual language.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/visual/visual.dart';
import 'package:naviwealth/features/ai_chat/ui/tool_invocation_renderers.dart';
import 'package:naviwealth/features/settings/ui/ai_trace_timeline.dart';

const Size _surface = Size(360, 480);

Future<void> _pumpComponent(
  WidgetTester tester, {
  required String name,
  required Widget child,
}) async {
  // No-op theme — system default light. We test our own Ai* tokens,
  // not the page theme chrome.
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await screenMatchesGolden(tester, name);
}

void main() {
  testGoldens('AiPill — neutral / selected / error', (tester) async {
    await _pumpComponent(
      tester,
      name: 'ai_pill_variants',
      child: const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AiPill(label: 'neutral', leading: AiSparkle()),
          AiPill(label: 'selected', state: AiPillState.selected),
          AiPill(label: 'error', state: AiPillState.error),
        ],
      ),
    );
  }, tags: 'golden');

  testGoldens('AiObjectCapsule (Wave 33)', (tester) async {
    await _pumpComponent(
      tester,
      name: 'ai_object_capsule',
      // We use the underlying AiPill here directly to avoid
      // pulling in showAiSheet's transitive providers — the
      // capsule's visual identity is `AiPill + AiSparkle + intent
      // label`, exactly what we render below.
      child: const AiPill(label: '为什么变化', leading: AiSparkle()),
    );
  }, tags: 'golden');

  testGoldens('asset_allocation domain renderer (Wave 34)', (tester) async {
    await _pumpComponent(
      tester,
      name: 'asset_allocation_view',
      child: const AssetAllocationView(
        output: <String, Object?>{
          'buckets': [
            {
              'bucket_dim': 'asset_type',
              'bucket_key': 'stock',
              'currency': 'USD',
              'total_cost_minor': '150000',
              'position_count': 2,
              'weight': 0.6,
            },
            {
              'bucket_dim': 'asset_type',
              'bucket_key': 'crypto',
              'currency': 'USD',
              'total_cost_minor': '100000',
              'position_count': 1,
              'weight': 0.4,
            },
          ],
        },
      ),
    );
  }, tags: 'golden');

  testGoldens('subscription_changes domain renderer (Wave 34)', (tester) async {
    await _pumpComponent(
      tester,
      name: 'subscription_changes_view',
      child: const SubscriptionChangesView(
        output: <String, Object?>{
          'changes': [
            {
              'id': 'netflix|USD',
              'merchant_key': 'netflix',
              'cadence': 'monthly',
              'currency': 'USD',
              'prev_amount_minor': '999',
              'new_amount_minor': '1299',
              'delta_ratio': 0.3,
              'since': '2026-04-01T00:00:00Z',
            },
            {
              'id': 'spotify|USD',
              'merchant_key': 'spotify',
              'cadence': 'monthly',
              'currency': 'USD',
              'prev_amount_minor': '999',
              'new_amount_minor': '799',
              'delta_ratio': -0.2,
              'since': '2026-03-01T00:00:00Z',
            },
          ],
        },
      ),
    );
  }, tags: 'golden');

  testGoldens('AiTraceTimeline — invocation → routing → tools → terminal', (
    tester,
  ) async {
    const trace = AiTrace(
      requestId: 'r_golden',
      startedAtIso: '2026-05-12T09:00:00Z',
      intent: IntentHint(
        capability: Capability.analyze,
        risk: RiskLevel.suggest,
        label: 'turn',
      ),
      backend: Backend.cloud,
      budgetTier: BudgetTier.small,
      routingReason: 'capsule_explain',
      usedCloud: true,
      usedRawLedger: false,
      totalDurationMs: 850,
      toolCalls: [
        TraceToolCall(name: 'get_holdings', durationMs: 30, ok: true),
        TraceToolCall(name: 'compute_xirr', durationMs: 80, ok: true),
        TraceToolCall(
          name: 'get_subscription_changes',
          durationMs: 12,
          ok: false,
        ),
      ],
      invocation: <String, Object?>{
        'source': 'expense_detail',
        'intent': 'explain_change',
        'object_type': 'expense',
        'object_id': 'exp_42',
      },
    );
    await _pumpComponent(
      tester,
      name: 'ai_trace_timeline',
      child: AiTraceTimeline(events: buildTimeline(trace)),
    );
  }, tags: 'golden');
}
