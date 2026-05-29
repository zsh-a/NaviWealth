// Wave 33 — IntentDescriptor registry invariants.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart'
    show kDomainFinance, kDomainHealth, kDomainKnowledge;
import 'package:naviwealth/core/ai/intent/intent.dart';

void main() {
  test('every registered intent has a non-empty label and prompt', () {
    for (final d in intentDescriptors) {
      expect(d.name, isNotEmpty);
      expect(d.labelZh, isNotEmpty);
      expect(d.promptTemplate, isNotEmpty);
    }
  });

  test('intent names are unique', () {
    final names = intentDescriptors.map((d) => d.name).toSet();
    expect(
      names.length,
      intentDescriptors.length,
      reason: 'duplicate intent name detected',
    );
  });

  test('lookupIntent returns the matching descriptor', () {
    final hit = lookupIntent('explain_change');
    expect(hit, isNotNull);
    expect(hit!.allowedObjectTypes, contains('expense'));
  });

  test('lookupIntent returns null for unknown name', () {
    expect(lookupIntent('does_not_exist'), isNull);
  });

  test('requiresExplicitConfirmation defaults to false', () {
    // §5.10.6 — registered read-only intents must never trip the guard.
    for (final d in intentDescriptors) {
      expect(
        d.requiresExplicitConfirmation,
        isFalse,
        reason:
            'Intent "${d.name}" must not silently require confirmation — '
            'flip the flag explicitly when registering a write-shaped intent.',
      );
    }
  });

  test('requiresExplicitConfirmation can be set on a descriptor', () {
    const d = IntentDescriptor(
      name: 'place_order',
      labelZh: '下单',
      allowedObjectTypes: <String>{'asset'},
      preferredCapabilities: <AiCapability>{AiCapability.proposal},
      promptTemplate: '请确认是否对 {{object_label}} 下单。',
      requiresExplicitConfirmation: true,
    );
    expect(d.requiresExplicitConfirmation, isTrue);
  });

  test('renderPromptFor fills object_label / timeframe / currency', () {
    const inv = AiIntentInvocation(
      source: 'expense_detail',
      intent: 'explain_change',
      object: AiObjectRef(type: 'expense', id: 'e1'),
      context: {'timeframe': '本月'},
      domain: kDomainFinance,
    );
    final prompt = renderPromptFor(inv, objectLabel: 'Netflix 订阅');
    expect(prompt, contains('Netflix 订阅'));
    expect(prompt, contains('本月'));
  });

  test('renderPromptFor falls back gracefully on missing context', () {
    const inv = AiIntentInvocation(
      source: 'x',
      intent: 'explain_change',
      object: AiObjectRef(type: 'expense', id: 'e1'),
      domain: kDomainFinance,
    );
    final prompt = renderPromptFor(inv);
    expect(prompt, contains('最近 30 天'));
  });

  test('single-domain intent: domains resolves to just its home domain', () {
    const d = IntentDescriptor(
      name: 'explain_change',
      labelZh: '为什么',
      allowedObjectTypes: <String>{'expense'},
      preferredCapabilities: <AiCapability>{AiCapability.chat},
      promptTemplate: '解释 {{object_label}}',
    );
    expect(d.domains, <String>{kDomainFinance});
    expect(intentAllowsDomain(d, kDomainFinance), isTrue);
    expect(intentAllowsDomain(d, kDomainHealth), isFalse);
  });

  test('cross-domain intent accepts home + allowedDomains', () {
    const d = IntentDescriptor(
      name: 'correlate_spend_sleep',
      labelZh: '开销 × 睡眠',
      allowedObjectTypes: <String>{},
      preferredCapabilities: <AiCapability>{AiCapability.chat},
      promptTemplate: '把我的开销和睡眠放在一起看。',
      allowedDomains: <String>{kDomainHealth},
    );
    expect(d.domains, <String>{kDomainFinance, kDomainHealth});
    expect(intentAllowsDomain(d, kDomainFinance), isTrue);
    expect(intentAllowsDomain(d, kDomainHealth), isTrue);
    expect(intentAllowsDomain(d, kDomainKnowledge), isFalse);
  });

  test('every registered intent allows its own home domain', () {
    for (final d in intentDescriptors) {
      expect(
        intentAllowsDomain(d, d.domain),
        isTrue,
        reason: 'intent "${d.name}" must accept its own domain',
      );
    }
  });

  test('toTraceJson is stable and includes source + intent + object', () {
    const inv = AiIntentInvocation(
      source: 'home_insight_card',
      intent: 'explain_insight',
      object: AiObjectRef(type: 'insight', id: 'anom_2026'),
      context: {'severity': 'warn'},
      domain: kDomainFinance,
    );
    final json = inv.toTraceJson();
    expect(json['source'], 'home_insight_card');
    expect(json['intent'], 'explain_insight');
    expect(json['object_type'], 'insight');
    expect(json['object_id'], 'anom_2026');
    expect(json['context_keys'], contains('severity'));
  });
}
