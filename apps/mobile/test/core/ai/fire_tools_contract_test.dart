import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/production_ai_catalog.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';

/// Static-contract test: every FIRE OS Phase-5 tool name must resolve in
/// both the registry (dispatchable) and the descriptor table
/// (metadata). Mirrors the broader W-D6 invariant for the full tool
/// catalog — adding a new tool here keeps the failure clear.
void main() {
  group('FIRE OS Phase 5 tool catalog', () {
    const expectedTools = <String>[
      'get_fire_state',
      'get_fire_plan',
      'get_fire_buckets',
      'get_fire_stress_tests',
      'get_fire_review',
      'simulate_fire_plan',
      'propose_fire_plan_update',
      'propose_fire_bucket_rule',
    ];

    final registry = productionDeviceToolRegistry;

    test('all 8 tools registered in the device registry', () {
      for (final name in expectedTools) {
        expect(
          registry.lookup(name),
          isNotNull,
          reason: 'tool $name is missing from the production device registry',
        );
      }
    });

    test('all 8 tools have descriptors with consistent shape', () {
      for (final name in expectedTools) {
        final desc = productionToolDescriptors[name];
        expect(desc, isNotNull, reason: 'descriptor missing for $name');
        if (name.startsWith('propose_')) {
          expect(desc!.access, Access.propose);
          expect(desc.sideEffect, SideEffect.deviceLocalWrite);
          expect(desc.requiresConfirmation, Confirmation.oneTap);
        } else {
          expect(desc!.access, Access.read);
          expect(desc.requiresConfirmation, Confirmation.none);
          expect(desc.sideEffect, SideEffect.none);
        }
      }
    });

    test('every device tool has a matching descriptor (no drift)', () {
      for (final name in registry.names) {
        expect(
          productionToolDescriptors[name],
          isNotNull,
          reason: 'registered tool $name has no descriptor',
        );
      }
    });
  });

  group('FIRE OS Phase 5 intents', () {
    const expectedIntents = <String>[
      'explain_fire_state',
      'review_cash_bucket',
      'simulate_fire_change',
      'explain_stress_test',
      'suggest_fire_actions',
    ];

    test('all 5 intents are registered in the policy', () {
      final catalog = productionIntentCatalog;
      for (final intent in expectedIntents) {
        expect(
          catalog.lookup(intent),
          isNotNull,
          reason: 'intent $intent missing from the production intent catalog',
        );
      }
    });

    test('intents target FIRE OS object types only', () {
      final catalog = productionIntentCatalog;
      for (final intent in expectedIntents) {
        final descriptor = catalog.lookup(intent)!;
        expect(
          descriptor.allowedObjectTypes.every((t) => t.startsWith('fire_')),
          isTrue,
          reason:
              'intent $intent allows non-FIRE object types: ${descriptor.allowedObjectTypes}',
        );
      }
    });
  });
}
