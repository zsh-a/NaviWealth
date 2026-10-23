import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/production_ai_catalog.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart';
import 'package:naviwealth/core/ai/contracts/privacy_budget.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/intent/intent.dart';

void main() {
  group('D-1.3 domain field', () {
    for (final domain in <AiDomain>[
      for (final scope in DomainScope.values) AiDomain.domain(scope),
      const AiDomain.shell(),
      const AiDomain.global(),
    ]) {
      test('AI contracts round-trip explicit ${domain.wire} ownership', () {
        final hint = IntentHint(
          domain: domain,
          capability: Capability.analyze,
          risk: RiskLevel.info,
        );
        final tool = ToolDescriptor(
          domain: domain,
          name: 'read_data',
          access: Access.read,
          risk: RiskLevel.info,
          requiresConfirmation: Confirmation.none,
          allowedContextTier: BudgetTier.small,
        );
        expect(hint.toJson()['domain'], domain.wire);
        expect(tool.toJson()['domain'], domain.wire);
        expect(IntentHint.fromJson(hint.toJson()).domain, domain);
        expect(ToolDescriptor.fromJson(tool.toJson()).domain, domain);
      });
    }

    for (final value in [null, '', 'life', 'settings', 'unregistered', 42]) {
      test('AI domain rejects missing or unknown wire value $value', () {
        expect(() => AiDomain.fromWire(value), throwsFormatException);
        expect(
          () => IntentHint.fromJson({
            'capability': 'analyze',
            'risk': 'info',
            'domain': value,
          }),
          throwsFormatException,
        );
        expect(
          () => ToolDescriptor.fromJson({'name': 'read_data', 'domain': value}),
          throwsFormatException,
        );
      });
    }

    test('built-in catalog tags each tool with the right LifeOS domain', () {
      ToolDescriptor lookup(String name) =>
          productionToolDescriptors.values.firstWhere((t) => t.name == name);
      expect(lookup('query_memory').domain, const AiDomain.shell());
      expect(lookup('build_context').domain, const AiDomain.shell());
      expect(
        lookup('get_holdings').domain,
        const AiDomain.domain(DomainScope.finance),
      );
      expect(
        lookup('propose_fire_plan_update').domain,
        const AiDomain.domain(DomainScope.finance),
      );
      expect(
        lookup('get_wheel_lifecycle').domain,
        const AiDomain.domain(DomainScope.finance),
      );
      expect(
        lookup('get_hrv_trend').domain,
        const AiDomain.domain(DomainScope.health),
      );
      expect(
        lookup('get_recovery_signal').domain,
        const AiDomain.domain(DomainScope.health),
      );
      expect(
        lookup('recall_decision').domain,
        const AiDomain.domain(DomainScope.knowledge),
      );
      expect(
        lookup('propose_capture').domain,
        const AiDomain.domain(DomainScope.knowledge),
      );
      expect(
        lookup('list_open_actions').domain,
        const AiDomain.domain(DomainScope.execution),
      );
      expect(
        lookup('propose_action').domain,
        const AiDomain.domain(DomainScope.execution),
      );
      const validDomains = <AiDomain>[
        AiDomain.domain(DomainScope.finance),
        AiDomain.shell(),
        AiDomain.domain(DomainScope.health),
        AiDomain.domain(DomainScope.knowledge),
        AiDomain.domain(DomainScope.execution),
      ];
      for (final t in productionToolDescriptors.values) {
        expect(
          validDomains.contains(t.domain),
          isTrue,
          reason: 'tool ${t.name} has unexpected domain ${t.domain.wire}',
        );
      }
    });

    test('AiIntentInvocation toTraceJson exposes the domain', () {
      const invocation = AiIntentInvocation(
        source: 'expense_detail',
        intent: 'explain_change',
        domain: AiDomain.domain(DomainScope.finance),
      );
      expect(invocation.domain, const AiDomain.domain(DomainScope.finance));
      expect(invocation.toTraceJson()['domain'], 'finance');

      const healthInv = AiIntentInvocation(
        source: 'sleep_card',
        intent: 'explain_recovery',
        domain: AiDomain.domain(DomainScope.health),
      );
      expect(healthInv.toTraceJson()['domain'], 'health');
    });

    test('IntentDescriptor retains explicit shell and business ownership', () {
      const descriptor = IntentDescriptor(
        domain: AiDomain.shell(),
        name: 'explain_change',
        allowedObjectTypes: <String>{'expense'},
        preferredCapabilities: <AiCapability>{AiCapability.chat},
      );
      expect(descriptor.domain, const AiDomain.shell());

      const healthDescriptor = IntentDescriptor(
        name: 'explain_recovery',
        allowedObjectTypes: <String>{'sleep_session'},
        preferredCapabilities: <AiCapability>{AiCapability.chat},
        domain: AiDomain.domain(DomainScope.health),
      );
      expect(
        healthDescriptor.domain,
        const AiDomain.domain(DomainScope.health),
      );
    });
  });
}
