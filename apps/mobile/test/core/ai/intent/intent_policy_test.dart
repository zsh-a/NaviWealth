// Wave 33 — IntentDescriptor registry invariants.

import 'package:flutter_test/flutter_test.dart';
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
    expect(names.length, intentDescriptors.length,
        reason: 'duplicate intent name detected');
  });

  test('lookupIntent returns the matching descriptor', () {
    final hit = lookupIntent('explain_change');
    expect(hit, isNotNull);
    expect(hit!.allowedObjectTypes, contains('expense'));
  });

  test('lookupIntent returns null for unknown name', () {
    expect(lookupIntent('does_not_exist'), isNull);
  });

  test('renderPromptFor fills object_label / timeframe / currency', () {
    const inv = AiIntentInvocation(
      source: 'expense_detail',
      intent: 'explain_change',
      object: AiObjectRef(type: 'expense', id: 'e1'),
      context: {'timeframe': '本月'},
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
    );
    final prompt = renderPromptFor(inv);
    expect(prompt, contains('最近 30 天'));
  });

  test('toTraceJson is stable and includes source + intent + object', () {
    const inv = AiIntentInvocation(
      source: 'home_insight_card',
      intent: 'explain_insight',
      object: AiObjectRef(type: 'insight', id: 'anom_2026'),
      context: {'severity': 'warn'},
    );
    final json = inv.toTraceJson();
    expect(json['source'], 'home_insight_card');
    expect(json['intent'], 'explain_insight');
    expect(json['object_type'], 'insight');
    expect(json['object_id'], 'anom_2026');
    expect(json['context_keys'], contains('severity'));
  });
}
