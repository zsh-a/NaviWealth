// Wave 43 — golden coverage for the AI visual language (Wave 36 tokens
// + Wave 37/38/39/40 surfaces).
//
// These goldens are intentionally component-scoped: one widget,
// deterministic inputs, minimal chrome.
//
// Coverage: 4 PNG baselines / 1 file
//   - ai_pill_variants
//   - ai_object_capsule
//   - asset_allocation_view (Wave 34 domain renderer)
//   - subscription_changes_view (Wave 34 domain renderer)
//
// Each golden runs at 360×N logical px, light theme, en locale. Drift
// either side and the golden breaks — protection against accidental
// Wave-36 token changes leaking into the visual language.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:naviwealth/core/ai/visual/visual.dart';
import 'package:naviwealth/features/ai_chat/ui/tool_invocation_renderers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '_golden_setup.dart';

const Size _surface = Size(360, 480);

Future<void> _pumpComponent(
  WidgetTester tester, {
  required String name,
  required Widget child,
}) async {
  // No-op theme — system default light. We test our own Ai* tokens,
  // not the page theme chrome.
  await loadGoldenFonts();
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await expectGoldenSurface('goldens/$name.png');
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
}
