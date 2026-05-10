/// Barrel for `lib/core/ai/local/skills/`. Each skill is a small,
/// pure unit (rules + types) that the router can dispatch to without
/// touching feature modules. Phase 3 will add nl_to_query_plan +
/// query_plan_executor.
library;

export 'context_compressor.dart';
export 'merchant_key.dart';
export 'recurring_detector.dart';
export 'refund_matcher.dart';
export 'transaction_input.dart';
export 'transfer_matcher.dart';
export 'txn_classifier.dart';
