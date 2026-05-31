/// Device-side `read_*_window` tool parameter validation.
///
/// This file previously held the full cloud disclosure protocol
/// (DisclosureRequest / DisclosureResponse / LedgerField / UserConsent /
/// AnonymizationLevel-keyed responses). The cloud planner is
/// gone, but the [DisclosurePurpose] enum is still useful: device
/// scoped-window tools require callers to declare *why* they're pulling
/// detail rows, and that requires a stable enumerated value.
///
/// Everything else in this file was removed by the 2026-05-24
/// boundary audit. See `docs/ai-boundary-audit.md`.
library;

enum DisclosurePurpose {
  drillDownExpense,
  drillDownInvestment,
  refundMatching,
  anomalyExplain,
  recurringDetect,
  other,
}

extension DisclosurePurposeWire on DisclosurePurpose {
  String get wire => switch (this) {
    DisclosurePurpose.drillDownExpense => 'drill_down_expense',
    DisclosurePurpose.drillDownInvestment => 'drill_down_investment',
    DisclosurePurpose.refundMatching => 'refund_matching',
    DisclosurePurpose.anomalyExplain => 'anomaly_explain',
    DisclosurePurpose.recurringDetect => 'recurring_detect',
    DisclosurePurpose.other => 'other',
  };

  static DisclosurePurpose parse(String s) => switch (s) {
    'drill_down_expense' => DisclosurePurpose.drillDownExpense,
    'drill_down_investment' => DisclosurePurpose.drillDownInvestment,
    'refund_matching' => DisclosurePurpose.refundMatching,
    'anomaly_explain' => DisclosurePurpose.anomalyExplain,
    'recurring_detect' => DisclosurePurpose.recurringDetect,
    _ => DisclosurePurpose.other,
  };
}
