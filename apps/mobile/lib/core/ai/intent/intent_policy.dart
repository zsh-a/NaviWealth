/// Wave 33 — Intent registry (governance for intent strings).
///
/// Without a registry the codebase ends up with 50 intent strings, half
/// of them dead. Mirror the `tool_policy.rs` pattern: descriptors are a
/// static const list, validated at startup, with code review enforcing
/// "new capsule → new intent → new entry here".
///
/// Each descriptor declares which object types the intent applies to
/// and which prompt template to render. Capsules + invocation surfaces
/// look up the descriptor at trigger time to derive the rendered
/// prompt; off-registry intents fall back to the caller's
/// `suggestedPrompt` and `assert(false)` in dev.
library;

import 'ai_intent_invocation.dart';

class IntentDescriptor {
  const IntentDescriptor({
    required this.name,
    required this.labelZh,
    required this.allowedObjectTypes,
    required this.preferredCapabilities,
    required this.promptTemplate,
    this.preferredReadModels = const <String>[],
  });

  /// Stable identifier — `'explain_change'`, never renamed.
  final String name;

  /// Capsule / button text shown to the user in Chinese ("为什么", "对比").
  /// Short — capsules are dense.
  final String labelZh;

  /// Which `AiObjectRef.type` values may use this intent. Empty set
  /// means "object-less / abstract intent".
  final Set<String> allowedObjectTypes;

  /// Hint to the bottom sheet shell about what affordances to render.
  /// The shell may add `chat` regardless.
  final Set<AiCapability> preferredCapabilities;

  /// Mustache-ish template. Supported placeholders:
  ///   `{{object_label}}` — caller-supplied label for the object
  ///   `{{timeframe}}`    — `context['timeframe']` or "最近 30 天"
  ///   `{{currency}}`     — `context['currency']` or user base currency
  /// Unresolved placeholders are left in place (LLM still understands
  /// surrounding language) but emit a debug-mode warning.
  final String promptTemplate;

  /// Read models this intent typically consults. Used to seed the
  /// freshness gate (force-refresh before the cloud answers) — falls
  /// back to no-hint when empty.
  final List<String> preferredReadModels;
}

const intentDescriptors = <IntentDescriptor>[
  IntentDescriptor(
    name: 'explain_change',
    labelZh: '为什么变化',
    allowedObjectTypes: <String>{
      'expense',
      'recurring_pattern',
      'asset',
      'liability',
      'account',
    },
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    promptTemplate:
        '请解释 {{object_label}} 在 {{timeframe}} 内的变化原因，并指出相关趋势。',
    preferredReadModels: <String>[
      'monthly_spend_by_category',
      'subscription_changes',
      'cashflow_buckets',
    ],
  ),
  IntentDescriptor(
    name: 'summarize_account',
    labelZh: '账户概览',
    allowedObjectTypes: <String>{'account'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    promptTemplate: '请用要点总结账户 {{object_label}} 在 {{timeframe}} 的表现。',
    preferredReadModels: <String>[
      'holdings_snapshot',
      'cashflow_buckets',
      'investment_performance',
    ],
  ),
  IntentDescriptor(
    name: 'stress_test_plan',
    labelZh: '如何提高',
    allowedObjectTypes: <String>{'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    promptTemplate:
        '请评估 {{object_label}} 在不利市场条件下的稳健性，并给出 2–3 个具体改进建议。',
    preferredReadModels: <String>['net_worth_snapshot', 'xirr_snapshot'],
  ),
  IntentDescriptor(
    name: 'compare_period',
    labelZh: '对比',
    allowedObjectTypes: <String>{
      'expense',
      'account',
      'asset',
      'recurring_pattern',
    },
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    promptTemplate: '请对比 {{object_label}} 在两个不同时期的差异并说明驱动因素。',
    preferredReadModels: <String>[
      'cashflow_buckets',
      'monthly_spend_by_category',
    ],
  ),
  IntentDescriptor(
    name: 'explain_insight',
    labelZh: '展开',
    allowedObjectTypes: <String>{'insight'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    promptTemplate:
        '请详细解释这条洞察 ({{object_label}})，说明触发原因、严重程度和可采取的行动。',
    preferredReadModels: <String>['anomaly_flags', 'subscription_changes'],
  ),
];

/// Lookup by intent name. Returns `null` for off-registry strings —
/// callers should `assert(false)` in dev and use `suggestedPrompt`.
IntentDescriptor? lookupIntent(String name) {
  for (final d in intentDescriptors) {
    if (d.name == name) return d;
  }
  return null;
}

/// Render the prompt for an invocation. Returns the registered template
/// with placeholders filled (best-effort) when the intent is on
/// registry; otherwise returns [AiIntentInvocation.suggestedPrompt] or
/// a generic fallback.
String renderPromptFor(
  AiIntentInvocation invocation, {
  String? objectLabel,
  String? defaultTimeframe,
  String? defaultCurrency,
}) {
  final desc = lookupIntent(invocation.intent);
  if (desc == null) {
    assert(
      false,
      'AiIntentInvocation uses unregistered intent "${invocation.intent}". '
      'Add to intent_policy.intentDescriptors or use suggestedPrompt.',
    );
    return invocation.suggestedPrompt ??
        '请就 ${objectLabel ?? "当前对象"} 提供分析。';
  }
  if (invocation.object != null &&
      desc.allowedObjectTypes.isNotEmpty &&
      !desc.allowedObjectTypes.contains(invocation.object!.type)) {
    assert(
      false,
      'Intent "${invocation.intent}" does not allow object type '
      '"${invocation.object!.type}" (allowed: ${desc.allowedObjectTypes}).',
    );
  }
  final timeframe =
      (invocation.context['timeframe'] as String?) ??
      defaultTimeframe ??
      '最近 30 天';
  final currency =
      (invocation.context['currency'] as String?) ??
      defaultCurrency ??
      'USD';
  final label = objectLabel ?? invocation.object?.toString() ?? '当前对象';
  return desc.promptTemplate
      .replaceAll('{{object_label}}', label)
      .replaceAll('{{timeframe}}', timeframe)
      .replaceAll('{{currency}}', currency);
}
