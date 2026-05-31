/// Rule-based transaction classifier.
///
/// One taxonomy drives three surfaces:
///  * transaction classification (`hint`),
///  * natural-language category extraction (`queryKeywords`),
///  * ledger write-back (`expenseSlug`).
///
/// Hints are aligned with the seeded Finance expense accounts where possible;
/// analytics can still use finer descriptors when safely inferred.
library;

import 'merchant_key.dart';
import 'transaction_input.dart';

class Classification {
  const Classification({
    required this.categoryHint,
    required this.confidence,
    required this.reason,
  });

  final String categoryHint;
  final double confidence;
  final String reason;
}

class _CategoryTaxon {
  const _CategoryTaxon({
    required this.hint,
    required this.expenseSlug,
    this.aliases = const <String>[],
    this.queryKeywords = const <String>[],
  });

  final String hint;
  final String expenseSlug;
  final List<String> aliases;
  final List<String> queryKeywords;
}

final RegExp _tokenRun = RegExp(r'[一-鿿]+|[a-z0-9]+');
final RegExp _cjkRun = RegExp(r'[一-鿿]');

const List<_CategoryTaxon> _taxonomy = <_CategoryTaxon>[
  _CategoryTaxon(
    hint: 'food_delivery',
    expenseSlug: 'dining',
    aliases: <String>[
      'uber eats',
      'ubereats',
      'doordash',
      'grubhub',
      'meituan',
      '美团外卖',
      '美团',
      '饿了么',
      'eleme',
    ],
    queryKeywords: <String>['外卖', 'delivery', 'food delivery'],
  ),
  _CategoryTaxon(
    hint: 'coffee',
    expenseSlug: 'coffee',
    aliases: <String>[
      'starbucks',
      'luckin',
      'blue bottle',
      'bluebottle',
      '星巴克',
      '瑞幸咖啡',
      '瑞幸',
      'manner',
    ],
    queryKeywords: <String>['咖啡', 'coffee'],
  ),
  _CategoryTaxon(
    hint: 'grocery',
    expenseSlug: 'groceries',
    aliases: <String>[
      'whole foods',
      'wholefoods',
      'safeway',
      'costco',
      'trader joes',
      'traderjoes',
      'walmart',
      '盒马',
      '沃尔玛',
    ],
    queryKeywords: <String>['日用', '生鲜', 'grocery'],
  ),
  _CategoryTaxon(
    hint: 'transport',
    expenseSlug: 'transport',
    aliases: <String>['uber', 'lyft', 'didi', '滴滴'],
    queryKeywords: <String>['打车', '出行'],
  ),
  _CategoryTaxon(
    hint: 'subscription',
    expenseSlug: 'subscriptions',
    aliases: <String>[
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
    ],
    queryKeywords: <String>['订阅', 'subscription'],
  ),
  _CategoryTaxon(
    hint: 'shopping',
    expenseSlug: 'shopping',
    aliases: <String>[
      'apple store',
      'applestore',
      'amazon',
      'taobao',
      '淘宝',
      '京东',
      'jd',
      'tmall',
      '天猫',
    ],
    queryKeywords: <String>['购物', 'shopping'],
  ),
  _CategoryTaxon(
    hint: 'utilities',
    expenseSlug: 'utilities',
    aliases: <String>[
      'verizon',
      'comcast',
      'pge',
      'pg&e',
      '中国移动',
      '中国联通',
      '国家电网',
    ],
    queryKeywords: <String>['水电', 'utilities'],
  ),
];

const Set<String> _expenseSlugs = <String>{
  'dining',
  'groceries',
  'coffee',
  'transport',
  'rideHailing',
  'housing',
  'utilities',
  'household',
  'entertainment',
  'medical',
  'fitness',
  'education',
  'shopping',
  'subscriptions',
  'travel',
  'communication',
  'familySupport',
  'gift',
  'pets',
  'trading',
  'tax',
  'other',
};

Classification? classifyTransaction(TransactionInput txn) {
  if (txn.categoryId != null) return null;
  if (parseAmountMinor(txn.amountMinor) >= 0) return null;
  return _classifyDescription(txn.description);
}

/// Analytics/query classification. Stored user categories are respected
/// except when they are broad parent buckets that this taxonomy owns and
/// can safely refine from the descriptor.
String? categoryHintForTransaction(TransactionInput txn) {
  if (parseAmountMinor(txn.amountMinor) >= 0) return null;
  final stored = categoryHintFromCategoryId(txn.categoryId);
  final inferred = _classifyDescription(txn.description)?.categoryHint;
  if (stored == null || stored == 'other') return inferred ?? stored;
  if (inferred != null && _canRefine(stored, inferred)) return inferred;
  return stored;
}

String expenseCategorySlugForHint(String? hint) {
  final canonical = _canonicalHint(hint);
  if (canonical == null) return 'other';
  return _taxonForHint(canonical)?.expenseSlug ??
      (_expenseSlugs.contains(canonical) ? canonical : 'other');
}

List<String>? categoryHintsForText(String input) {
  final descriptor = _descriptor(input);
  if (descriptor.normalized.isEmpty) return null;

  final matches = <_TaxonMatch>[];
  for (final taxon in _taxonomy) {
    for (final term in <String>[...taxon.queryKeywords, ...taxon.aliases]) {
      final normalized = _normalize(term);
      if (normalized.isEmpty) continue;
      if (_matchesTerm(descriptor, normalized, term)) {
        matches.add(
          _TaxonMatch(taxon: taxon, term: term, normalized: normalized),
        );
      }
    }
  }
  return _selectHints(matches);
}

String? categoryHintFromCategoryId(String? categoryId) {
  if (categoryId == null || categoryId.trim().isEmpty) return null;
  final direct = _canonicalHint(categoryId);
  if (direct != null) return direct;

  final segments = categoryId
      .toLowerCase()
      .split(RegExp(r'[:/]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  final expenseIndex = segments.indexOf('expense');
  if (expenseIndex < 0 || expenseIndex + 1 >= segments.length) return null;
  final slug = segments[expenseIndex + 1];
  return _expenseSlugs.contains(slug) ? slug : null;
}

Classification? _classifyDescription(String description) {
  final key = merchantKey(description);
  final descriptor = _descriptor(description);
  if (key.isEmpty || descriptor.normalized.isEmpty) return null;
  final match = _bestMatch(descriptor);
  if (match == null) return null;
  final exactMerchant = key == match.normalized;
  return Classification(
    categoryHint: match.taxon.hint,
    confidence: exactMerchant ? 0.9 : 0.82,
    reason: exactMerchant
        ? 'merchant alias matched: $key'
        : 'descriptor alias matched: ${match.term}',
  );
}

_TaxonMatch? _bestMatch(_Descriptor descriptor) {
  final matches = <_TaxonMatch>[];
  for (final taxon in _taxonomy) {
    for (final alias in taxon.aliases) {
      final normalized = _normalize(alias);
      if (normalized.isEmpty) continue;
      if (_matchesTerm(descriptor, normalized, alias)) {
        matches.add(
          _TaxonMatch(taxon: taxon, term: alias, normalized: normalized),
        );
      }
    }
  }
  if (matches.isEmpty) return null;
  matches.sort((a, b) => b.normalized.length.compareTo(a.normalized.length));
  return matches.first;
}

List<String>? _selectHints(List<_TaxonMatch> matches) {
  matches.sort((a, b) => b.normalized.length.compareTo(a.normalized.length));
  final selectedTerms = <String>[];
  final hints = <String>{};
  for (final match in matches) {
    final shadowed = selectedTerms.any(
      (term) => term != match.normalized && term.contains(match.normalized),
    );
    if (shadowed) continue;
    hints.add(match.taxon.hint);
    selectedTerms.add(match.normalized);
  }
  return hints.isEmpty ? null : hints.toList(growable: false);
}

bool _canRefine(String stored, String inferred) {
  final taxon = _taxonForHint(inferred);
  return taxon != null && taxon.expenseSlug == stored;
}

String? _canonicalHint(String? input) {
  if (input == null) return null;
  final normalized = _normalize(input);
  if (normalized.isEmpty) return null;
  for (final taxon in _taxonomy) {
    if (normalized == _normalize(taxon.hint)) return taxon.hint;
    if (normalized == _normalize(taxon.expenseSlug)) return taxon.expenseSlug;
    for (final term in <String>[...taxon.queryKeywords, ...taxon.aliases]) {
      if (normalized == _normalize(term)) return taxon.hint;
    }
  }
  for (final slug in _expenseSlugs) {
    if (normalized == _normalize(slug)) return slug;
  }
  return null;
}

_CategoryTaxon? _taxonForHint(String hint) {
  for (final taxon in _taxonomy) {
    if (taxon.hint == hint) return taxon;
  }
  return null;
}

bool _matchesTerm(
  _Descriptor descriptor,
  String normalizedTerm,
  String rawTerm,
) {
  if (descriptor.normalized == normalizedTerm) return true;
  if (descriptor.tokens.contains(normalizedTerm)) return true;
  if (_isPhrase(rawTerm) || _canMatchInside(normalizedTerm)) {
    return descriptor.normalized.contains(normalizedTerm);
  }
  return false;
}

bool _isPhrase(String rawTerm) =>
    _tokens(rawTerm).length > 1 || _cjkRun.hasMatch(rawTerm);

bool _canMatchInside(String normalizedTerm) => normalizedTerm.length >= 6;

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

class _TaxonMatch {
  const _TaxonMatch({
    required this.taxon,
    required this.term,
    required this.normalized,
  });

  final _CategoryTaxon taxon;
  final String term;
  final String normalized;
}
