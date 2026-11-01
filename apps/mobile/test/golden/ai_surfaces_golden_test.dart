// AI component goldens use the production Material, Forui and semantic themes.
// Both appearances follow the default refined preset.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/visual/visual.dart';
import 'package:naviwealth/features/ai_chat/ui/tools/renderers/tool_invocation_renderers.dart';

import '_golden_setup.dart';

const Size _surface = Size(360, 480);

Future<void> _pumpComponent(
  WidgetTester tester, {
  required String name,
  required GoldenTheme variant,
  required Widget child,
}) => pumpAndSnapshotMobile(
  tester,
  name: name,
  variant: variant,
  logicalSize: _surface,
  devicePixelRatio: 1,
  child: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

void main() {
  for (final variant in [GoldenTheme.light, GoldenTheme.dark]) {
    group(variant.name, () {
      testVisualGolden('AiPill — neutral / selected / error', (tester) async {
        await _pumpComponent(
          tester,
          variant: variant,
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

      testVisualGolden('AiObjectCapsule (Wave 33)', (tester) async {
        await _pumpComponent(
          tester,
          variant: variant,
          name: 'ai_object_capsule',
          // We use the underlying AiPill here directly to avoid
          // pulling in showAiSheet's transitive providers — the
          // capsule's visual identity is `AiPill + AiSparkle + intent
          // label`, exactly what we render below.
          child: const AiPill(label: '为什么变化', leading: AiSparkle()),
        );
      }, tags: 'golden');

      testVisualGolden('asset_allocation domain renderer (Wave 34)', (
        tester,
      ) async {
        await _pumpComponent(
          tester,
          variant: variant,
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

      testVisualGolden('subscription_changes domain renderer (Wave 34)', (
        tester,
      ) async {
        await _pumpComponent(
          tester,
          variant: variant,
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
    });
  }
}
