/// Wave 34 — Reply chip generator (rules-based v1).
///
/// Picks 3 follow-up suggestions to show under a completed assistant
/// turn. The signal is intentionally crude: hashed off the invocation
/// intent (Wave 33) and the set of tool names the assistant used in
/// the turn. A future revision can ship an end-side classifier; v1's
/// job is to *prove the surface* and start logging which chips users
/// actually tap.
///
/// Calm Intelligence (§5.6): chips are typography-first, outline,
/// no icons. Suggestions are object-semantic phrases, not generic
/// "Ask AI" copy.
library;

/// Generate up to 3 chips to show under [turnTools] for a turn that
/// originated from [invocationIntent] (nullable — chat-tab manual turns
/// have no invocation). When nothing matches the rules, returns the
/// generic fallback set.
List<String> suggestReplyChips({
  String? invocationIntent,
  Set<String> turnTools = const <String>{},
}) {
  final out = <String>[];
  // Cap intent-specific picks at 2 so a tool-driven chip can always
  // surface when the assistant actually used a tool. The third slot
  // is reserved for tool / generic fallback.
  const intentCap = 2;

  void addFromIntent(String chip) {
    if (out.length >= intentCap) return;
    if (out.contains(chip)) return;
    out.add(chip);
  }

  void add(String chip) {
    if (out.length >= 3) return;
    if (out.contains(chip)) return;
    out.add(chip);
  }

  // ─ Intent-specific top picks (capped at 2) ──────────────────
  switch (invocationIntent) {
    case 'explain_change':
      addFromIntent('对比上一周期');
      addFromIntent('找出主要驱动');
      addFromIntent('如何控制支出');
    case 'summarize_account':
      addFromIntent('看持仓明细');
      addFromIntent('计算 XIRR');
      addFromIntent('对比上月');
    case 'stress_test_plan':
      addFromIntent('如果市场下跌 20%?');
      addFromIntent('需要每月多存多少?');
      addFromIntent('调整资产配置建议');
    case 'compare_period':
      addFromIntent('再对比一个时段');
      addFromIntent('哪些类目变化最大');
      addFromIntent('给出趋势小结');
    case 'explain_insight':
      addFromIntent('如何处理这条洞察?');
      addFromIntent('看历史相似情况');
      addFromIntent('给我具体行动方案');
  }

  // ─ Tool-driven suggestions ──────────────────────────────────
  // Add tool-tied chips that complement what the model just did.
  if (turnTools.contains('get_asset_allocation')) {
    add('风险集中度评估');
  }
  if (turnTools.contains('get_recurring_patterns')) {
    add('哪些订阅没在用');
  }
  if (turnTools.contains('get_subscription_changes')) {
    add('取消最贵的订阅?');
  }
  if (turnTools.contains('get_refund_links')) {
    add('未匹配的退款');
  }
  if (turnTools.contains('compute_xirr') ||
      turnTools.contains('get_xirr_summary')) {
    add('与基准对比');
  }
  if (turnTools.contains('compute_net_worth')) {
    add('未来 12 月预测');
  }

  // ─ Generic fallback ─────────────────────────────────────────
  add('展开细节');
  add('给出行动方案');
  add('与上月对比');

  return out.take(3).toList(growable: false);
}
