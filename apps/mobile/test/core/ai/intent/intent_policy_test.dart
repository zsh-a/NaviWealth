// Wave 33 — IntentDescriptor registry invariants.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart'
    show kDomainFinance, kDomainHealth, kDomainKnowledge;
import 'package:naviwealth/core/ai/intent/intent.dart';
import 'package:naviwealth/l10n/gen/app_localizations_zh.dart';

void main() {
  test('every registered intent resolves localized copy', () {
    final l10n = AppLocalizationsZh();
    final resolver = localizedIntentCopyResolver(l10n);
    for (final d in intentDescriptors) {
      expect(d.name, isNotEmpty);
      expect(resolver(d).label, isNotEmpty);
      expect(resolver(d).promptTemplate, isNotEmpty);
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
      allowedObjectTypes: <String>{'asset'},
      preferredCapabilities: <AiCapability>{AiCapability.proposal},
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
    final l10n = AppLocalizationsZh();
    final prompt = renderPromptFor(
      inv,
      objectLabel: 'Netflix 订阅',
      copyResolver: localizedIntentCopyResolver(l10n),
    );
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
    final l10n = AppLocalizationsZh();
    final prompt = renderPromptFor(
      inv,
      defaultTimeframe: l10n.aiIntentDefaultTimeframe,
      copyResolver: localizedIntentCopyResolver(l10n),
    );
    expect(prompt, contains('最近 30 天'));
  });

  test('renderPromptFor can use localized intent copy', () {
    const inv = AiIntentInvocation(
      source: 'chart',
      intent: 'explain_chart',
      object: AiObjectRef(type: 'chart', id: 'net_worth'),
      domain: kDomainFinance,
    );
    final l10n = AppLocalizationsZh();
    final prompt = renderPromptFor(
      inv,
      objectLabel: '净值趋势',
      defaultTimeframe: l10n.aiIntentDefaultTimeframe,
      copyResolver: localizedIntentCopyResolver(l10n),
      fallbackObjectLabel: l10n.aiIntentCurrentObject,
      fallbackPromptTemplate: l10n.aiIntentFallbackPrompt('{{object_label}}'),
    );

    expect(localizedIntentLabel(l10n, lookupIntent('explain_chart')), '问这张图');
    expect(prompt, contains('净值趋势'));
    expect(prompt, contains('最近 30 天'));
  });

  test('single-domain intent: domains resolves to just its home domain', () {
    const d = IntentDescriptor(
      name: 'explain_change',
      allowedObjectTypes: <String>{'expense'},
      preferredCapabilities: <AiCapability>{AiCapability.chat},
    );
    expect(d.domains, <String>{kDomainFinance});
    expect(intentAllowsDomain(d, kDomainFinance), isTrue);
    expect(intentAllowsDomain(d, kDomainHealth), isFalse);
  });

  test('cross-domain intent accepts home + allowedDomains', () {
    const d = IntentDescriptor(
      name: 'correlate_spend_sleep',
      allowedObjectTypes: <String>{},
      preferredCapabilities: <AiCapability>{AiCapability.chat},
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
