/// Rule-based transaction classifier.
///
/// Phase 2-B baseline: a static alias table maps transaction descriptors
/// to category *hints* (free-form strings — feature adapters map them to
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

class _CategoryRule {
  const _CategoryRule(this.categoryHint, this.aliases);

  final String categoryHint;
  final List<String> aliases;
}

final RegExp _tokenRun = RegExp(r'[一-鿿]+|[a-z0-9]+');

const List<_CategoryRule> _rules = <_CategoryRule>[
  _CategoryRule('food_delivery', <String>[
    'uber eats',
    'ubereats',
    'doordash',
    'grubhub',
    'meituan',
    '美团外卖',
    '美团',
    '饿了么',
    'eleme',
  ]),
  _CategoryRule('coffee', <String>[
    'starbucks',
    'luckin',
    'blue bottle',
    'bluebottle',
    '星巴克',
    '瑞幸咖啡',
    '瑞幸',
    'manner',
  ]),
  _CategoryRule('grocery', <String>[
    'whole foods',
    'wholefoods',
    'safeway',
    'costco',
    'trader joes',
    'traderjoes',
    'walmart',
    '盒马',
    '沃尔玛',
  ]),
  _CategoryRule('transport', <String>['uber', 'lyft', 'didi', '滴滴']),
  _CategoryRule('subscription', <String>[
    'netflix',
    'spotify',
    'apple music',
    'apple.com/bill',
    'icloud',
    'dropbox',
    'github',
    'openai',
    '腾讯视频',
    '爱奇艺',
  ]),
  _CategoryRule('shopping', <String>[
    'apple store',
    'applestore',
    'amazon',
    'taobao',
    '淘宝',
    '京东',
    'jd',
    'tmall',
    '天猫',
  ]),
  _CategoryRule('utilities', <String>[
    'verizon',
    'comcast',
    'pge',
    'pg&e',
    '中国移动',
    '中国联通',
    '国家电网',
  ]),
];

const Map<String, String> _queryCategoryAliases = <String, String>{
  '咖啡': 'coffee',
  'coffee': 'coffee',
  '外卖': 'food_delivery',
  'delivery': 'food_delivery',
  '订阅': 'subscription',
  'subscription': 'subscription',
  '日用': 'grocery',
  '生鲜': 'grocery',
  'grocery': 'grocery',
  '打车': 'transport',
  '出行': 'transport',
  '购物': 'shopping',
  'shopping': 'shopping',
  '水电': 'utilities',
  'utilities': 'utilities',
};

const Map<String, String> _hintToExpenseSlug = <String, String>{
  'coffee': 'food',
  'food_delivery': 'food',
  'grocery': 'food',
  'transport': 'transport',
  'subscription': 'entertainment',
  'shopping': 'shopping',
  'utilities': 'communication',
  'food': 'food',
  'household': 'household',
  'housing': 'housing',
  'entertainment': 'entertainment',
  'medical': 'medical',
  'education': 'education',
  'travel': 'travel',
  'communication': 'communication',
  'gift': 'gift',
  'tax': 'tax',
  'other': 'other',
};

/// Classify [txn]. Returns `null` when:
///  * The transaction already has a [TransactionInput.categoryId]
///    (the user has already chosen — never override),
///  * The amount is not an outflow,
///  * The descriptor is empty,
///  * No alias matches (the rules layer doesn't guess).
Classification? classifyTransaction(TransactionInput txn) {
  if (txn.categoryId != null) return null;
  if (parseAmountMinor(txn.amountMinor) >= 0) return null;
  return _classifyDescription(txn.description);
}

/// Best-effort category hint for analytics/query use. Unlike
/// [classifyTransaction], this can refine an existing broad ledger account
/// from the transaction description, then falls back to the stored category.
String? categoryHintForTransaction(TransactionInput txn) {
  if (parseAmountMinor(txn.amountMinor) >= 0) return null;
  final fromDescription = _classifyDescription(txn.description)?.categoryHint;
  if (fromDescription != null) return fromDescription;
  return categoryHintFromCategoryId(txn.categoryId);
}

/// Convert a category hint into the existing Finance expense account slug.
/// Unknown or model-supplied free-form values collapse to `other`.
String expenseCategorySlugForHint(String? hint) {
  if (hint == null) return 'other';
  final lower = hint.toLowerCase().trim();
  return _hintToExpenseSlug[lower] ??
      _hintToExpenseSlug[_normalizeHint(hint)] ??
      'other';
}

/// Extract one or more category hints from a natural-language query.
List<String>? categoryHintsForText(String input) {
  final normalized = input.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  final hits = <String>{};
  for (final entry in _queryCategoryAliases.entries) {
    if (normalized.contains(entry.key)) hits.add(entry.value);
  }

  final descriptor = _descriptor(normalized);
  final ruleMatches = <_RuleMatch>[];
  for (final rule in _rules) {
    for (final alias in rule.aliases) {
      final normalizedAlias = _normalize(alias);
      if (normalizedAlias.isEmpty) continue;
      if (_matchesAlias(descriptor, normalizedAlias)) {
        ruleMatches.add(
          _RuleMatch(
            categoryHint: rule.categoryHint,
            alias: alias,
            normalizedAlias: normalizedAlias,
          ),
        );
      }
    }
  }
  ruleMatches.sort(
    (a, b) => b.normalizedAlias.length.compareTo(a.normalizedAlias.length),
  );
  final selectedAliases = <String>[];
  for (final match in ruleMatches) {
    final shadowed = selectedAliases.any(
      (alias) =>
          alias != match.normalizedAlias &&
          alias.contains(match.normalizedAlias),
    );
    if (shadowed) continue;
    hits.add(match.categoryHint);
    selectedAliases.add(match.normalizedAlias);
  }
  return hits.isEmpty ? null : hits.toList(growable: false);
}

String? categoryHintFromCategoryId(String? categoryId) {
  if (categoryId == null || categoryId.isEmpty) return null;
  final lower = categoryId.toLowerCase().trim();
  if (_hintToExpenseSlug.containsKey(lower)) return lower;
  final normalized = _normalizeHint(categoryId);
  if (_hintToExpenseSlug.containsKey(normalized)) return normalized;
  final expenseIndex = normalized.indexOf('expense');
  if (expenseIndex < 0) return null;
  final tail = normalized.substring(expenseIndex + 'expense'.length);
  for (final slug in _hintToExpenseSlug.values.toSet()) {
    if (tail == slug || tail.startsWith(slug)) return slug;
  }
  return null;
}

Classification? _classifyDescription(String description) {
  final key = merchantKey(description);
  final descriptor = _descriptor(description);
  if (key.isEmpty || descriptor.normalized.isEmpty) return null;
  final match = _bestRuleMatch(descriptor);
  if (match == null) return null;
  final exactMerchant = key == match.normalizedAlias;
  return Classification(
    categoryHint: match.categoryHint,
    confidence: exactMerchant ? 0.9 : 0.82,
    reason: exactMerchant
        ? 'merchant alias matched: $key'
        : 'descriptor alias matched: ${match.alias}',
  );
}

String _normalizeHint(String input) =>
    input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9一-鿿]+'), '');

_RuleMatch? _bestRuleMatch(_Descriptor descriptor) {
  _RuleMatch? best;
  for (final rule in _rules) {
    for (final alias in rule.aliases) {
      final normalizedAlias = _normalize(alias);
      if (normalizedAlias.isEmpty) continue;
      if (!_matchesAlias(descriptor, normalizedAlias)) continue;
      final candidate = _RuleMatch(
        categoryHint: rule.categoryHint,
        alias: alias,
        normalizedAlias: normalizedAlias,
      );
      if (best == null ||
          candidate.normalizedAlias.length > best.normalizedAlias.length) {
        best = candidate;
      }
    }
  }
  return best;
}

bool _matchesAlias(_Descriptor descriptor, String normalizedAlias) {
  if (descriptor.normalized == normalizedAlias) return true;
  if (descriptor.tokens.contains(normalizedAlias)) return true;
  if (_isPhraseAlias(normalizedAlias)) {
    return descriptor.normalized.contains(normalizedAlias);
  }
  return false;
}

bool _isPhraseAlias(String normalizedAlias) {
  for (final rule in _rules) {
    for (final alias in rule.aliases) {
      if (_normalize(alias) == normalizedAlias) {
        return _tokens(alias).length > 1 || RegExp(r'[一-鿿]').hasMatch(alias);
      }
    }
  }
  return false;
}

_Descriptor _descriptor(String input) {
  final tokens = _tokens(input);
  return _Descriptor(tokens: tokens, normalized: tokens.join());
}

List<String> _tokens(String input) => _tokenRun
    .allMatches(input.toLowerCase())
    .map((m) => m.group(0)!)
    .toList(growable: false);

String _normalize(String input) => _tokens(input).join();

class _Descriptor {
  const _Descriptor({required this.tokens, required this.normalized});

  final List<String> tokens;
  final String normalized;
}

class _RuleMatch {
  const _RuleMatch({
    required this.categoryHint,
    required this.alias,
    required this.normalizedAlias,
  });

  final String categoryHint;
  final String alias;
  final String normalizedAlias;
}
