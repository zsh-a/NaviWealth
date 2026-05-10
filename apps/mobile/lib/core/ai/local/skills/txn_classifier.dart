/// Rule-based transaction classifier.
///
/// Phase 2-B baseline: a static alias table maps merchant keys to
/// category *hints* (free-form strings — feature adapters map them to
/// real category ids). High-confidence matches return 0.9; ambiguous
/// or near-misses are intentionally left to the user.
///
/// This skill is the warm path for ~99% of transactions: rules cover
/// the long tail of common merchants without paying for an LLM call.
/// When rules miss, the higher-tier path (Phase 5 device LLM) takes
/// over — but that's an opt-in upgrade, not a Phase 2 dependency.
library;

import 'merchant_key.dart';
import 'transaction_input.dart';

class Classification {
  const Classification({
    required this.categoryHint,
    required this.confidence,
    required this.reason,
  });

  /// Free-form category hint. Feature-side adapters map this to a
  /// concrete category id ('coffee' → `kCategoryCoffee`, etc.). Keeps
  /// the skill independent of the project's category schema.
  final String categoryHint;

  /// 0.0 to 1.0. The classifier returns nothing when it's not
  /// confident enough — it never guesses.
  final double confidence;

  /// Short human-readable rationale for tracing / debugging
  /// (`'merchant alias matched: starbucks'`).
  final String reason;
}

const Map<String, String> _aliasToCategory = <String, String>{
  // Coffee
  'starbucks': 'coffee',
  'luckin': 'coffee',
  'bluebottle': 'coffee',
  '星巴克': 'coffee',
  '瑞幸': 'coffee',
  'manner': 'coffee',
  // Food delivery
  'doordash': 'food_delivery',
  'ubereats': 'food_delivery',
  'grubhub': 'food_delivery',
  'meituan': 'food_delivery',
  '美团': 'food_delivery',
  '饿了么': 'food_delivery',
  // Grocery
  'wholefoods': 'grocery',
  'safeway': 'grocery',
  'costco': 'grocery',
  'traderjoes': 'grocery',
  '盒马': 'grocery',
  '沃尔玛': 'grocery',
  // Transport
  'uber': 'transport',
  'lyft': 'transport',
  'didi': 'transport',
  '滴滴': 'transport',
  // Subscription / digital
  'netflix': 'subscription',
  'spotify': 'subscription',
  'apple': 'subscription',
  'icloud': 'subscription',
  'dropbox': 'subscription',
  'github': 'subscription',
  'openai': 'subscription',
  '腾讯视频': 'subscription',
  '爱奇艺': 'subscription',
  // Shopping (broad)
  'amazon': 'shopping',
  'taobao': 'shopping',
  '淘宝': 'shopping',
  '京东': 'shopping',
  'jd': 'shopping',
  'tmall': 'shopping',
  '天猫': 'shopping',
  // Utilities
  'verizon': 'utilities',
  'comcast': 'utilities',
  'pg&e': 'utilities',
  '中国移动': 'utilities',
  '中国联通': 'utilities',
  '国家电网': 'utilities',
};

/// Classify [txn]. Returns `null` when:
///  * The transaction already has a [TransactionInput.categoryId]
///    (the user has already chosen — never override),
///  * The merchant key is empty (description had no letters),
///  * No alias matches (the rules layer doesn't guess).
Classification? classifyTransaction(TransactionInput txn) {
  if (txn.categoryId != null) return null;
  final key = merchantKey(txn.description);
  if (key.isEmpty) return null;

  // Exact match first — highest confidence.
  final exact = _aliasToCategory[key];
  if (exact != null) {
    return Classification(
      categoryHint: exact,
      confidence: 0.9,
      reason: 'merchant alias matched: $key',
    );
  }

  // Substring fallback. Common for Chinese merchant strings where
  // the extracted key is `'美团外卖'` and the alias is `'美团'`. Pick
  // the *longest* matching alias so 'amazonfresh' (if added) wins
  // over the broader 'amazon'.
  String? best;
  for (final alias in _aliasToCategory.keys) {
    if (!key.contains(alias)) continue;
    if (best == null || alias.length > best.length) best = alias;
  }
  if (best != null) {
    return Classification(
      categoryHint: _aliasToCategory[best]!,
      confidence: 0.8,
      reason: 'merchant alias substring match: $best',
    );
  }
  return null;
}
