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
    this.requiresExplicitConfirmation = false,
    this.domain = 'finance',
  });

  /// Stable identifier — `'explain_change'`, never renamed.
  final String name;

  /// LifeOS domain this intent belongs to. Phase D-1.3 default
  /// `finance`; Phase D-2 will introduce `health` intents.
  final String domain;

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

  /// §5.10.6 — irreversible-operation guard. When `true`, surfaces that
  /// could trigger this intent (command palette overlay, inline capsule
  /// auto-actions) **must not** execute it without an explicit
  /// confirmation sheet. The rule is enforced at the call site (command
  /// palette / capsule dispatcher); AI surfaces never short-circuit a
  /// transfer / order / delete via natural language.
  ///
  /// Reach for this on any intent whose side effect is not safely
  /// undoable through [DriftUndoStack]: external API calls, cross-account
  /// transfers, account deletion, broker order placement.
  final bool requiresExplicitConfirmation;
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
    promptTemplate: '请解释 {{object_label}} 在 {{timeframe}} 内的变化原因，并指出相关趋势。',
    preferredReadModels: <String>[
      'subscription_changes',
      'recurring_patterns',
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
    promptTemplate: '请评估 {{object_label}} 在不利市场条件下的稳健性，并给出 2–3 个具体改进建议。',
    preferredReadModels: <String>[
      'net_worth_snapshot',
      'holdings_snapshot',
      'investment_performance',
    ],
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
    preferredReadModels: <String>['cashflow_buckets'],
  ),
  IntentDescriptor(
    name: 'explain_insight',
    labelZh: '展开',
    allowedObjectTypes: <String>{'insight'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    promptTemplate: '请详细解释这条洞察 ({{object_label}})，说明触发原因、严重程度和可采取的行动。',
    preferredReadModels: <String>[
      'anomaly_flags',
      'subscription_changes',
      'refund_links',
    ],
  ),
  IntentDescriptor(
    name: 'explain_chart',
    labelZh: '问这张图',
    // Charts are abstract — they don't carry a stable AiObjectRef of
    // their own. Allowed types stays empty so any chart-bearing
    // surface can pass an `AiObjectRef(type: 'chart', id: '<chart>')`
    // without tripping the registry's type-mismatch assertion.
    allowedObjectTypes: <String>{'chart'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    promptTemplate:
        '请解释这张图 ({{object_label}}) 在 {{timeframe}} 内的关键变化，以及背后的驱动因素。',
    preferredReadModels: <String>[
      'net_worth_snapshot',
      'cashflow_buckets',
      'holdings_snapshot',
    ],
  ),
  IntentDescriptor(
    name: 'transactions.explainSelection',
    labelZh: '解读',
    allowedObjectTypes: <String>{'transactions'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    promptTemplate: '请解读用户选中的这些交易 ({{object_label}})，给出共同点 / 异常 / 可能归类。',
    preferredReadModels: <String>[
      'cashflow_buckets',
      'subscription_changes',
      'refund_links',
    ],
  ),
  // FIRE OS Phase 5 intents — explain / suggest / simulate / propose.
  IntentDescriptor(
    name: 'explain_fire_state',
    labelZh: '解读 FIRE 状态',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    promptTemplate:
        '请基于 get_fire_state 的结果，向我解释当前 {{object_label}} 的安全等级、提取率、现金桶覆盖和 FIRE ETA，并指出最值得关注的一两条 suggested_actions。',
    preferredReadModels: <String>[
      'fire_state',
      'net_worth_snapshot',
      'cashflow_buckets',
    ],
  ),
  IntentDescriptor(
    name: 'review_cash_bucket',
    labelZh: '检查现金桶',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    promptTemplate:
        '请用 get_fire_buckets 检查当前现金桶覆盖月数,如低于目标 {{object_label}} 请给出补足金额，并准备好 propose_fire_plan_update 或 propose_fire_bucket_rule 的建议。',
    preferredReadModels: <String>['fire_state', 'fire_buckets'],
  ),
  IntentDescriptor(
    name: 'simulate_fire_change',
    labelZh: '模拟一下',
    allowedObjectTypes: <String>{'fire_plan', 'fire_state'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    promptTemplate:
        '请用 simulate_fire_plan 模拟 {{object_label}} 的变化(支出、结余、SWR、现金桶月数等)对 FIRE 状态的影响。明确告诉我这只是模拟，没有写入计划。',
    // `simulate_fire_plan` does not start with `get_` so the corpus
    // normaliser does not strip it; list it verbatim.
    preferredReadModels: <String>[
      'fire_state',
      'fire_plan',
      'simulate_fire_plan',
    ],
  ),
  IntentDescriptor(
    name: 'explain_stress_test',
    labelZh: '解释压力测试',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    promptTemplate:
        '请基于 get_fire_stress_tests 的结果逐条解释市场回撤 / 支出上升 / 一次性冲击 / 汇率冲击 / 现金桶耗尽对 {{object_label}} 的影响。强调这是韧性检验，不是预测。',
    preferredReadModels: <String>['fire_state', 'fire_stress_tests'],
  ),
  IntentDescriptor(
    name: 'suggest_fire_actions',
    labelZh: '下一步怎么办',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    promptTemplate:
        '请基于 get_fire_state 的 suggested_actions 给出三件最值得做的事；若涉及计划改动，请用 propose_fire_plan_update 让我确认。',
    preferredReadModels: <String>[
      'fire_state',
      'fire_buckets',
      'fire_stress_tests',
    ],
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
    return invocation.suggestedPrompt ?? '请就 ${objectLabel ?? "当前对象"} 提供分析。';
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
      (invocation.context['currency'] as String?) ?? defaultCurrency ?? 'USD';
  final label = objectLabel ?? invocation.object?.toString() ?? '当前对象';
  return desc.promptTemplate
      .replaceAll('{{object_label}}', label)
      .replaceAll('{{timeframe}}', timeframe)
      .replaceAll('{{currency}}', currency);
}
