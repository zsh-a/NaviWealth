/// Barrel for FinanceOS local analytical skills.
///
/// These helpers are pure Dart and run on device, but they are Finance-owned:
/// transaction descriptors, merchant keys, recurring payments, refunds,
/// transfers, duplicate charges, subscriptions, and expense classification.
library;

export 'duplicate_charge_detector.dart';
export 'merchant_key.dart';
export 'recurring_detector.dart';
export 'refund_matcher.dart';
export 'subscription_change_detector.dart';
export 'transaction_descriptor_match.dart';
export 'transaction_input.dart';
export 'transfer_matcher.dart';
export 'txn_classifier.dart';
