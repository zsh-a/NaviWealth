import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart';
import 'package:naviwealth/core/ai/contracts/privacy_budget.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/intent/ai_intent_invocation.dart';
import 'package:naviwealth/core/ai/intent/intent_policy.dart';

void main() {
  group('D-1.3 domain field', () {
    test('IntentHint defaults to finance and round-trips', () {
      const hint = IntentHint(
        capability: Capability.analyze,
        risk: RiskLevel.info,
      );
      expect(hint.domain, kDomainFinance);
      final restored = IntentHint.fromJson(hint.toJson());
      expect(restored.domain, kDomainFinance);
    });

    test('IntentHint preserves a non-finance domain', () {
      const hint = IntentHint(
        capability: Capability.summarize,
        risk: RiskLevel.suggest,
        domain: 'health',
      );
      final restored = IntentHint.fromJson(hint.toJson());
      expect(restored.domain, 'health');
    });

    test('IntentHint legacy JSON without domain decodes to finance', () {
      final legacy = <String, Object?>{
        'capability': 'analyze',
        'risk': 'info',
      };
      expect(IntentHint.fromJson(legacy).domain, kDomainFinance);
    });

    test('ToolDescriptor defaults to finance and round-trips', () {
      const tool = ToolDescriptor(
        name: 'get_holdings',
        access: Access.read,
        risk: RiskLevel.info,
        requiresConfirmation: Confirmation.none,
        allowedContextTier: BudgetTier.small,
      );
      expect(tool.domain, kDomainFinance);
      expect(ToolDescriptor.fromJson(tool.toJson()).domain, kDomainFinance);
    });

    test('ToolDescriptor preserves shell / health domains', () {
      const shellTool = ToolDescriptor(
        name: 'build_context',
        access: Access.read,
        risk: RiskLevel.info,
        requiresConfirmation: Confirmation.none,
        allowedContextTier: BudgetTier.standard,
        domain: kDomainShell,
      );
      expect(shellTool.domain, kDomainShell);
      expect(ToolDescriptor.fromJson(shellTool.toJson()).domain, kDomainShell);

      const healthTool = ToolDescriptor(
        name: 'get_recovery_signal',
        access: Access.read,
        risk: RiskLevel.info,
        requiresConfirmation: Confirmation.none,
        allowedContextTier: BudgetTier.small,
        domain: 'health',
      );
      expect(
        ToolDescriptor.fromJson(healthTool.toJson()).domain,
        'health',
      );
    });

    test('ToolDescriptor legacy JSON without domain decodes to finance', () {
      final legacy = <String, Object?>{
        'name': 'get_holdings',
        'access': 'read',
        'risk': 'info',
        'requires_confirmation': 'none',
        'allowed_context_tier': 'small',
      };
      expect(ToolDescriptor.fromJson(legacy).domain, kDomainFinance);
    });

    test('built-in catalog tags each tool with the right LifeOS domain', () {
      ToolDescriptor lookup(String name) =>
          allToolDescriptors.firstWhere((t) => t.name == name);
      expect(lookup('query_memory').domain, kDomainShell);
      expect(lookup('build_context').domain, kDomainShell);
      expect(lookup('get_holdings').domain, kDomainFinance);
      expect(lookup('propose_fire_plan_update').domain, kDomainFinance);
      expect(lookup('get_wheel_lifecycle').domain, kDomainFinance);
      expect(lookup('get_hrv_trend').domain, kDomainHealth);
      expect(lookup('get_recovery_signal').domain, kDomainHealth);
      expect(lookup('recall_decision').domain, kDomainKnowledge);
      expect(lookup('propose_inbox_classification').domain, kDomainKnowledge);
      const validDomains = <String>{
        kDomainFinance,
        kDomainShell,
        kDomainHealth,
        kDomainKnowledge,
      };
      for (final t in allToolDescriptors) {
        expect(
          validDomains.contains(t.domain),
          isTrue,
          reason: 'tool ${t.name} has unexpected domain ${t.domain}',
        );
      }
    });

    test('AiIntentInvocation toTraceJson exposes the domain', () {
      const invocation = AiIntentInvocation(
        source: 'expense_detail',
        intent: 'explain_change',
      );
      expect(invocation.domain, kDomainFinance);
      expect(invocation.toTraceJson()['domain'], kDomainFinance);

      const healthInv = AiIntentInvocation(
        source: 'sleep_card',
        intent: 'explain_recovery',
        domain: 'health',
      );
      expect(healthInv.toTraceJson()['domain'], 'health');
    });

    test('IntentDescriptor defaults to finance, accepts non-finance', () {
      const descriptor = IntentDescriptor(
        name: 'explain_change',
        labelZh: '为什么',
        allowedObjectTypes: <String>{'expense'},
        preferredCapabilities: <AiCapability>{AiCapability.chat},
        promptTemplate: '解释 {{object_label}}',
      );
      expect(descriptor.domain, kDomainFinance);

      const healthDescriptor = IntentDescriptor(
        name: 'explain_recovery',
        labelZh: '恢复',
        allowedObjectTypes: <String>{'sleep_session'},
        preferredCapabilities: <AiCapability>{AiCapability.chat},
        promptTemplate: '解释 {{object_label}} 的恢复趋势',
        domain: 'health',
      );
      expect(healthDescriptor.domain, 'health');
    });
  });
}
