/// Barrel for `lib/core/ai/local/skills/`. Each skill is a small,
/// pure unit (rules + types) that the router can dispatch to without
/// touching feature modules. Phase 3 will add nl_to_query_plan +
/// query_plan_executor.
library;

export 'context_compressor.dart';
// `drift_query_plan_executor` and `expense_to_transaction_input` moved
// to `features/finance/ai_tools/` — they import finance domain types.
export 'duplicate_charge_detector.dart';
export 'finance_query_plan.dart';
export 'merchant_key.dart';
export 'nl_to_query_plan.dart';
export 'query_plan_executor.dart';
export 'recurring_detector.dart';
export 'refund_matcher.dart';
export 'subscription_change_detector.dart';
export 'transaction_descriptor_match.dart';
export 'transaction_input.dart';
export 'transfer_matcher.dart';
export 'txn_classifier.dart';
