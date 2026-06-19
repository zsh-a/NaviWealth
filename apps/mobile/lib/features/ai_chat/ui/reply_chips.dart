/// Reply chip generator (rules-based v1).
///
/// Picks up to 3 follow-up suggestions to show under a completed
/// assistant turn. The signal is intentionally crude: hashed off the
/// invocation intent and the set of tool names the assistant
/// used in the turn. A future revision can ship an end-side classifier.
///
/// [suggestReplyChips] returns **stable chip ids**, not display text, so
/// the rule engine stays locale-independent and unit-testable without a
/// BuildContext. The UI resolves each id to a localized phrase via
/// [localizedReplyChip] right before rendering (and sends that localized
/// phrase as the user's next turn).
///
/// Calm Intelligence (§5.6): chips are typography-first, outline,
/// no icons. Suggestions are object-semantic phrases, not generic
/// generic assistant copy.
library;

import '../../../l10n/gen/app_localizations.dart';

/// Generate up to 3 chip ids to show under [turnTools] for a turn that
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
      addFromIntent('compareLastPeriod');
      addFromIntent('findKeyDrivers');
      addFromIntent('howControlSpending');
    case 'summarize_account':
      addFromIntent('viewHoldings');
      addFromIntent('computeXirr');
      addFromIntent('compareLastMonth');
    case 'stress_test_plan':
      addFromIntent('marketDrop20');
      addFromIntent('monthlySaveDelta');
      addFromIntent('rebalanceAdvice');
    case 'compare_period':
      addFromIntent('compareAnotherPeriod');
      addFromIntent('biggestCategoryChange');
      addFromIntent('trendSummary');
    case 'explain_insight':
      addFromIntent('handleInsight');
      addFromIntent('similarHistory');
      addFromIntent('actionPlan');
  }

  // ─ Tool-driven suggestions ──────────────────────────────────
  // Add tool-tied chips that complement what the model just did.
  if (turnTools.contains('get_asset_allocation')) {
    add('riskConcentration');
  }
  if (turnTools.contains('get_recurring_patterns')) {
    add('unusedSubscriptions');
  }
  if (turnTools.contains('get_subscription_changes')) {
    add('cancelPriciestSub');
  }
  if (turnTools.contains('get_refund_links')) {
    add('unmatchedRefunds');
  }
  if (turnTools.contains('compute_xirr') ||
      turnTools.contains('get_xirr_summary')) {
    add('compareBenchmark');
  }
  if (turnTools.contains('compute_net_worth')) {
    add('forecast12mo');
  }

  // ─ Generic fallback ─────────────────────────────────────────
  add('expandDetails');
  add('actionPlanGeneric');
  add('vsLastMonth');

  return out.take(3).toList(growable: false);
}

/// Resolve a chip id from [suggestReplyChips] to its localized phrase.
/// Unknown ids fall back to the generic "expand details" copy so a new
/// rule that ships before its string never renders a raw id.
String localizedReplyChip(AppLocalizations l10n, String id) {
  return switch (id) {
    'compareLastPeriod' => l10n.aiReplyChipCompareLastPeriod,
    'findKeyDrivers' => l10n.aiReplyChipFindKeyDrivers,
    'howControlSpending' => l10n.aiReplyChipHowControlSpending,
    'viewHoldings' => l10n.aiReplyChipViewHoldings,
    'computeXirr' => l10n.aiReplyChipComputeXirr,
    'compareLastMonth' => l10n.aiReplyChipCompareLastMonth,
    'marketDrop20' => l10n.aiReplyChipMarketDrop20,
    'monthlySaveDelta' => l10n.aiReplyChipMonthlySaveDelta,
    'rebalanceAdvice' => l10n.aiReplyChipRebalanceAdvice,
    'compareAnotherPeriod' => l10n.aiReplyChipCompareAnotherPeriod,
    'biggestCategoryChange' => l10n.aiReplyChipBiggestCategoryChange,
    'trendSummary' => l10n.aiReplyChipTrendSummary,
    'handleInsight' => l10n.aiReplyChipHandleInsight,
    'similarHistory' => l10n.aiReplyChipSimilarHistory,
    'actionPlan' => l10n.aiReplyChipActionPlan,
    'riskConcentration' => l10n.aiReplyChipRiskConcentration,
    'unusedSubscriptions' => l10n.aiReplyChipUnusedSubscriptions,
    'cancelPriciestSub' => l10n.aiReplyChipCancelPriciestSub,
    'unmatchedRefunds' => l10n.aiReplyChipUnmatchedRefunds,
    'compareBenchmark' => l10n.aiReplyChipCompareBenchmark,
    'forecast12mo' => l10n.aiReplyChipForecast12mo,
    'expandDetails' => l10n.aiReplyChipExpandDetails,
    'actionPlanGeneric' => l10n.aiReplyChipActionPlanGeneric,
    'vsLastMonth' => l10n.aiReplyChipVsLastMonth,
    _ => l10n.aiReplyChipExpandDetails,
  };
}
