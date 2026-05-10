/// Barrel for `lib/core/ai/local/skills/`. Each skill is a small,
/// pure unit (rules + types) that the router can dispatch to without
/// touching feature modules. Phase 2 will add txn_classifier,
/// recurring_detector, transfer_matcher, refund_matcher; Phase 3
/// adds nl_to_query_plan + query_plan_executor.
library;

export 'context_compressor.dart';
