/// Frozen regression corpus.
///
/// Per registered intent (see `intent_policy.dart`), one or more
/// representative prompts plus the **tool names** we expect the
/// upstream LLM to dispatch. The corpus is asserted at two layers:
///
///   1. **Static contract check** (this commit, `test/.../regression_corpus_test.dart`):
///        - every `intent` is registered in `intent_policy.dart`
///        - every `expectedTools` name resolves to a known tool
///          (either has a `renderToolOutput` renderer, or is on the
///          documented JSON-fallback allowlist)
///        - every `intent` × `expectedTools` pair is consistent with
///          the intent descriptor's `preferredReadModels`
///        Runs in every PR CI.
///
///   2. **Live LLM regression** (future nightly job — extension point
///      below): pump each prompt through a runtime that hits
///      Anthropic, capture the dispatched tool names, fail if the
///      union of dispatched tools doesn't include `expectedTools`.
///      Catches: SYSTEM_PROMPT regression, tool descriptor schema
///      drift, upstream model behaviour change, freshness gate
///      brokenness. Requires API credentials + a $/run budget and is
///      not wired in this commit.
///
/// Add prompts to widen coverage. Removing prompts requires a
/// `// coverage shrink rationale: …` comment.
library;

class RegressionPrompt {
  const RegressionPrompt({
    required this.id,
    required this.intent,
    required this.userPrompt,
    required this.expectedTools,
    this.objectType,
    this.objectId,
  });

  /// Stable identifier — used in failure reports and to allowlist
  /// individual flaky prompts in the future.
  final String id;

  /// Must match an `IntentDescriptor.name` in `intent_policy.dart`.
  final String intent;

  /// The literal prompt sent to the runtime (after intent template
  /// expansion). Keep these short and unambiguous so brittleness
  /// stays bounded.
  final String userPrompt;

  /// At least one of these tool names must appear in the LLM's
  /// dispatched tool calls. Empty set = "any tool answer is fine"
  /// (used for free-form intents — currently none).
  final Set<String> expectedTools;

  /// Optional object context used to construct the
  /// `AiIntentInvocation` for the runtime smoke. Mirrors what a real
  /// capsule tap would inject.
  final String? objectType;
  final String? objectId;
}

/// Allowlist of tool names that are wire-side but **don't** have a
/// custom mobile renderer (raw-JSON viewer in `ToolInvocationCard` is
/// the intended UX). The static contract check uses this so we don't
/// false-positive a missing renderer for tools that genuinely don't
/// need one.
///
/// Adding here ≈ "we know this tool dispatches but the JSON viewer
/// is good enough for now". Removing here ≈ "we need to write a
/// custom renderer for this tool".
const Set<String> jsonOnlyRenderTools = <String>{
  // Read models with simple tabular outputs (number + currency +
  // optional breakdown). The raw JSON is short and the LLM mostly
  // narrates the numbers in prose anyway.
  'get_cashflow_buckets',
  'get_net_worth_summary',
  'get_anomaly_flags',
  'get_investment_performance',
  // FIRE OS Phase 5 — the hero / buckets / stress / review surfaces
  // render the numbers natively on the FIRE page; the chat sheet
  // falls back to JSON until a custom renderer lands.
  'get_fire_state',
  'get_fire_plan',
  'get_fire_buckets',
  'get_fire_stress_tests',
  'get_fire_review',
  'simulate_fire_plan',
};

const List<RegressionPrompt> regressionCorpus = <RegressionPrompt>[
  // ── explain_change ─────────────────────────────────────────────
  RegressionPrompt(
    id: 'explain_change.expense_netflix',
    intent: 'explain_change',
    userPrompt: '为什么 Netflix 这个月比上月贵了？',
    expectedTools: <String>{
      'get_subscription_changes',
      'get_recurring_patterns',
    },
    objectType: 'expense',
    objectId: 'exp_netflix',
  ),
  RegressionPrompt(
    id: 'explain_change.spending_jump',
    intent: 'explain_change',
    userPrompt: '本月支出比上月多了 18%，主要花在哪？',
    expectedTools: <String>{'get_cashflow_buckets'},
  ),

  // ── summarize_account ──────────────────────────────────────────
  RegressionPrompt(
    id: 'summarize_account.broker_portfolio',
    intent: 'summarize_account',
    userPrompt: '帮我总结一下这个券商账户的近况',
    expectedTools: <String>{'get_holdings', 'get_investment_performance'},
    objectType: 'account',
    objectId: 'acc_broker',
  ),

  // ── stress_test_plan ───────────────────────────────────────────
  RegressionPrompt(
    id: 'stress_test_plan.fire',
    intent: 'stress_test_plan',
    userPrompt: '如果市场再下跌 20%，我的 FIRE 计划还稳吗？',
    expectedTools: <String>{
      'get_net_worth_summary',
      'get_investment_performance',
    },
    objectType: 'fire_plan',
    objectId: 'plan_default',
  ),

  // ── compare_period ─────────────────────────────────────────────
  RegressionPrompt(
    id: 'compare_period.cashflow',
    intent: 'compare_period',
    userPrompt: '对比 Q1 和 Q2 的现金流',
    expectedTools: <String>{'get_cashflow_buckets'},
  ),

  // ── explain_insight ────────────────────────────────────────────
  RegressionPrompt(
    id: 'explain_insight.anomaly',
    intent: 'explain_insight',
    userPrompt: '展开这条洞察：本月食品支出异常',
    expectedTools: <String>{'get_anomaly_flags', 'get_subscription_changes'},
    objectType: 'insight',
    objectId: 'anom_2026_05_food_spike',
  ),
  RegressionPrompt(
    id: 'explain_insight.refunds_pending',
    intent: 'explain_insight',
    userPrompt: '我有几笔退款还没到账？',
    expectedTools: <String>{'get_refund_links'},
    objectType: 'insight',
    objectId: 'pending_refunds',
  ),

  // ── explain_chart (§5.10 Layer 2 — chart-card capsule) ─────────
  RegressionPrompt(
    id: 'explain_chart.net_worth_trend',
    intent: 'explain_chart',
    userPrompt: '请解释这张净资产趋势图最近 12 个月的变化。',
    expectedTools: <String>{'get_net_worth_summary', 'get_cashflow_buckets'},
    objectType: 'chart',
    objectId: 'net_worth_trend',
  ),
  RegressionPrompt(
    id: 'explain_chart.allocation_pie',
    intent: 'explain_chart',
    userPrompt: '请解释这张资产配置图的关键变化。',
    expectedTools: <String>{'get_holdings'},
    objectType: 'chart',
    objectId: 'asset_allocation',
  ),

  // ── transactions.explainSelection (Layer 2 — selection toolbar) ─
  RegressionPrompt(
    id: 'transactions.explainSelection.three_coffee_charges',
    intent: 'transactions.explainSelection',
    userPrompt: '解读这 3 笔咖啡支出的共同点和异常。',
    expectedTools: <String>{'get_cashflow_buckets', 'get_subscription_changes'},
    objectType: 'transactions',
    objectId: 'sel_coffee_3',
  ),

  // ── FIRE OS Phase 5 intents (docs/roadmap-fire-os.md §5.3) ─────
  RegressionPrompt(
    id: 'explain_fire_state.headline',
    intent: 'explain_fire_state',
    userPrompt: '我现在的 FIRE 状态怎么样？提取率有没有问题？',
    expectedTools: <String>{'get_fire_state'},
    objectType: 'fire_state',
    objectId: 'default',
  ),
  RegressionPrompt(
    id: 'review_cash_bucket.shortfall',
    intent: 'review_cash_bucket',
    userPrompt: '我的现金桶够用吗？要不要补？',
    expectedTools: <String>{'get_fire_buckets', 'get_fire_state'},
    objectType: 'fire_state',
    objectId: 'default',
  ),
  RegressionPrompt(
    id: 'simulate_fire_change.expense_up',
    intent: 'simulate_fire_change',
    userPrompt: '如果月度支出上调 20%，我的 FIRE 状态会怎么样？',
    expectedTools: <String>{'simulate_fire_plan'},
    objectType: 'fire_plan',
    objectId: 'default',
  ),
  RegressionPrompt(
    id: 'explain_stress_test.market_drawdown',
    intent: 'explain_stress_test',
    userPrompt: '如果市场再跌 35%，我的计划撑得住吗？',
    expectedTools: <String>{'get_fire_stress_tests'},
    objectType: 'fire_state',
    objectId: 'default',
  ),
  RegressionPrompt(
    id: 'suggest_fire_actions.next_steps',
    intent: 'suggest_fire_actions',
    userPrompt: '基于当前 FIRE 状态，给我三件最值得做的事。',
    expectedTools: <String>{'get_fire_state'},
    objectType: 'fire_state',
    objectId: 'default',
  ),
];
