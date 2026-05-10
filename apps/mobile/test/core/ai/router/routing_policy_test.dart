import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/router/router.dart';

void main() {
  group('classify / search', () {
    test('classify always routes device, small tier, no confirmation', () {
      for (final online in <bool>[true, false]) {
        final d = decideRouting(
          RoutingInputs(
            intent: const IntentHint(
              capability: Capability.classify,
              risk: RiskLevel.commit,
            ),
            online: online,
          ),
        );
        expect(d.backend, Backend.device);
        expect(d.budgetTier, BudgetTier.small);
        expect(d.confirmation, Confirmation.none);
        expect(d.reason.code, 'classify_local');
        expect(d.supported, isTrue);
      }
    });

    test('search routes device regardless of online', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.search,
            risk: RiskLevel.info,
          ),
          online: false,
        ),
      );
      expect(d.backend, Backend.device);
      expect(d.reason.code, 'search_local');
    });
  });

  group('summarize', () {
    test('without device LLM falls back to template, small tier', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.summarize,
            risk: RiskLevel.info,
          ),
          online: true,
        ),
      );
      expect(d.backend, Backend.device);
      expect(d.budgetTier, BudgetTier.small);
      expect(d.reason.code, 'summarize_template');
    });

    test('with device LLM uses standard tier', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.summarize,
            risk: RiskLevel.info,
          ),
          online: true,
          deviceLlmReady: true,
        ),
      );
      expect(d.backend, Backend.device);
      expect(d.budgetTier, BudgetTier.standard);
      expect(d.reason.code, 'summarize_device_llm');
    });
  });

  group('analyze', () {
    test('online + standard sensitivity → hybrid', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.analyze,
            risk: RiskLevel.suggest,
          ),
          online: true,
        ),
      );
      expect(d.backend, Backend.hybrid);
      expect(d.budgetTier, BudgetTier.standard);
      expect(d.reason.code, 'analyze_hybrid');
    });

    test('strict sensitivity collapses to device', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.analyze,
            risk: RiskLevel.suggest,
          ),
          online: true,
          sensitivity: PrivacySensitivity.strict,
        ),
      );
      expect(d.backend, Backend.device);
      expect(d.reason.code, 'analyze_strict_local');
    });

    test('offline without device LLM → template', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.analyze,
            risk: RiskLevel.info,
          ),
          online: false,
        ),
      );
      expect(d.backend, Backend.device);
      expect(d.reason.code, 'analyze_offline_template');
    });

    test('offline with device LLM uses on-device LLM', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.analyze,
            risk: RiskLevel.info,
          ),
          online: false,
          deviceLlmReady: true,
        ),
      );
      expect(d.backend, Backend.device);
      expect(d.reason.code, 'analyze_offline_device_llm');
    });
  });

  group('plan', () {
    test('online + standard → hybrid, large tier', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.plan,
            risk: RiskLevel.propose,
          ),
          online: true,
        ),
      );
      expect(d.backend, Backend.hybrid);
      expect(d.budgetTier, BudgetTier.large);
      expect(d.confirmation, Confirmation.oneTap);
      expect(d.reason.code, 'plan_cloud');
      expect(d.supported, isTrue);
    });

    test('offline → unsupported with user-visible reason', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.plan,
            risk: RiskLevel.suggest,
          ),
          online: false,
        ),
      );
      expect(d.supported, isFalse);
      expect(d.reason.code, 'plan_requires_online');
      expect(d.reason.messageZh, isNotNull);
    });

    test('strict sensitivity → unsupported', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.plan,
            risk: RiskLevel.suggest,
          ),
          online: true,
          sensitivity: PrivacySensitivity.strict,
        ),
      );
      expect(d.supported, isFalse);
      expect(d.reason.code, 'plan_strict_disabled');
    });
  });

  group('write — by side-effect scope', () {
    test('local + commit → device, no confirmation (relies on undo)', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.write,
            risk: RiskLevel.commit,
            sideEffect: SideEffectScope.local,
          ),
          online: true,
        ),
      );
      expect(d.backend, Backend.device);
      expect(d.confirmation, Confirmation.none);
      expect(d.reason.code, 'write_local');
    });

    test('local + propose → device, oneTap', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.write,
            risk: RiskLevel.propose,
            sideEffect: SideEffectScope.local,
          ),
          online: true,
        ),
      );
      expect(d.backend, Backend.device);
      expect(d.confirmation, Confirmation.oneTap);
    });

    test('cross-cutting + online → hybrid, oneTap', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.write,
            risk: RiskLevel.propose,
            sideEffect: SideEffectScope.crossCutting,
          ),
          online: true,
        ),
      );
      expect(d.backend, Backend.hybrid);
      expect(d.confirmation, Confirmation.oneTap);
      expect(d.reason.code, 'write_cross_cutting_cloud');
    });

    test('cross-cutting + offline → unsupported', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.write,
            risk: RiskLevel.propose,
            sideEffect: SideEffectScope.crossCutting,
          ),
          online: false,
        ),
      );
      expect(d.supported, isFalse);
      expect(d.reason.code, 'write_cross_cutting_requires_online');
    });

    test('external → typed confirmation, hybrid', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.write,
            risk: RiskLevel.commit,
            sideEffect: SideEffectScope.external,
          ),
          online: true,
        ),
      );
      expect(d.backend, Backend.hybrid);
      expect(d.confirmation, Confirmation.typed);
      expect(d.reason.code, 'write_external_typed');
    });

    test('external + offline → unsupported (never silently retry)', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.write,
            risk: RiskLevel.commit,
            sideEffect: SideEffectScope.external,
          ),
          online: false,
        ),
      );
      expect(d.supported, isFalse);
      expect(d.reason.code, 'write_external_requires_online');
    });

    test('write without sideEffect declared defaults to cross-cutting (safer)', () {
      final d = decideRouting(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.write,
            risk: RiskLevel.propose,
            // sideEffect intentionally omitted
          ),
          online: true,
        ),
      );
      expect(d.backend, Backend.hybrid);
      expect(d.confirmation, Confirmation.oneTap);
    });
  });

  group('AiRouter trace seeding', () {
    test('seeds trace with frozen clock and matches decision', () {
      final clock = DateTime.utc(2026, 5, 10, 10, 30);
      final router = AiRouter(now: () => clock);
      final decision = router.decide(
        const RoutingInputs(
          intent: IntentHint(
            capability: Capability.analyze,
            risk: RiskLevel.suggest,
            label: 'cashflow_explain',
          ),
          online: true,
        ),
      );
      final trace = router.seedTrace(
        requestId: 'req-1',
        decision: decision,
      );
      expect(trace.requestId, 'req-1');
      expect(trace.startedAtIso, '2026-05-10T10:30:00.000Z');
      expect(trace.intent.label, 'cashflow_explain');
      expect(trace.backend, Backend.hybrid);
      expect(trace.usedCloud, isTrue);
      expect(trace.usedRawLedger, isFalse);
      expect(trace.routingReason, 'analyze_hybrid');
    });
  });
}
