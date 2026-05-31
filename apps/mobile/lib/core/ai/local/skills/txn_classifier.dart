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

import 'package:naviwealth/domain/values/expense_category_taxonomy.dart';

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
  return _canonicalCategory(hint)?.slug ?? 'other';
}

List<String>? categoryHintsForText(String input) {
  final descriptor = _descriptor(input);
  if (descriptor.normalized.isEmpty) return null;

  final matches = <_TaxonMatch>[];
  for (final category in kExpenseCategoryTaxonomy) {
    for (final term in <String>[
      ...category.queryKeywords,
      ...category.merchantAliases,
    ]) {
      final normalized = _normalize(term);
      if (normalized.isEmpty) continue;
      if (_matchesTerm(descriptor, normalized, term)) {
        matches.add(
          _TaxonMatch(category: category, term: term, normalized: normalized),
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
  final slug = segments.skip(expenseIndex + 1).join(':');
  return isExpenseCategorySlug(slug) ? slug : null;
}

Classification? _classifyDescription(String description) {
  final key = merchantKey(description);
  final descriptor = _descriptor(description);
  if (key.isEmpty || descriptor.normalized.isEmpty) return null;
  final match = _bestMatch(descriptor);
  if (match == null) return null;
  final exactMerchant = key == match.normalized;
  return Classification(
    categoryHint: match.category.slug,
    confidence: exactMerchant ? 0.9 : 0.82,
    reason: exactMerchant
        ? 'merchant alias matched: $key'
        : 'descriptor alias matched: ${match.term}',
  );
}

_TaxonMatch? _bestMatch(_Descriptor descriptor) {
  final matches = <_TaxonMatch>[];
  for (final category in kExpenseCategoryTaxonomy) {
    for (final alias in category.merchantAliases) {
      final normalized = _normalize(alias);
      if (normalized.isEmpty) continue;
      if (_matchesTerm(descriptor, normalized, alias)) {
        matches.add(
          _TaxonMatch(category: category, term: alias, normalized: normalized),
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
    hints.add(match.category.slug);
    selectedTerms.add(match.normalized);
  }
  return hints.isEmpty ? null : hints.toList(growable: false);
}

bool _canRefine(String stored, String inferred) {
  return stored == inferred;
}

String? _canonicalHint(String? input) {
  return _canonicalCategory(input)?.slug;
}

ExpenseCategoryDefinition? _canonicalCategory(String? input) =>
    input == null ? null : expenseCategoryByInput(input);

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
    _tokens(rawTerm).length > 1 || expenseCategoryCjkRun.hasMatch(rawTerm);

bool _canMatchInside(String normalizedTerm) => normalizedTerm.length >= 6;

_Descriptor _descriptor(String input) {
  final tokens = _tokens(input);
  return _Descriptor(tokens: tokens, normalized: tokens.join());
}

List<String> _tokens(String input) => expenseCategoryTokenRun
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
    required this.category,
    required this.term,
    required this.normalized,
  });

  final ExpenseCategoryDefinition category;
  final String term;
  final String normalized;
}
