/// Descriptor similarity for transaction reconciliation.
///
/// This is deliberately narrower than [merchantKey]. A first-token merchant
/// key is useful for broad grouping, but it is too weak to decide that two
/// rows are the same ledger event.
library;

import 'merchant_key.dart';

enum TransactionDescriptorMatch { none, weakMerchant, strong }

extension TransactionDescriptorMatchX on TransactionDescriptorMatch {
  bool get isStrong => this == TransactionDescriptorMatch.strong;
}

final RegExp _tokenRun = RegExp(r'[一-鿿]+|[a-z0-9]+');
final RegExp _hasNamedChar = RegExp(r'[一-鿿a-z]');

const Set<String> _genericDescriptions = <String>{
  'unknown',
  'unknownvendor',
  'unnamedtransaction',
  'transaction',
  '未命名交易',
  '未知交易',
  '未知商户',
};

TransactionDescriptorMatch compareTransactionDescriptions(String a, String b) {
  final aNorm = _normalizedDescription(a);
  final bNorm = _normalizedDescription(b);
  if (aNorm.isEmpty || bNorm.isEmpty) return TransactionDescriptorMatch.none;
  if (_isGeneric(aNorm) || _isGeneric(bNorm)) {
    return TransactionDescriptorMatch.none;
  }
  if (aNorm == bNorm && _hasNamedChar.hasMatch(aNorm)) {
    return TransactionDescriptorMatch.strong;
  }

  final aKey = merchantKey(a);
  final bKey = merchantKey(b);
  if (aKey.isEmpty || aKey != bKey) return TransactionDescriptorMatch.none;

  final aTokens = _descriptionTokens(a);
  final bTokens = _descriptionTokens(b);
  if (aTokens.isEmpty || bTokens.isEmpty) {
    return TransactionDescriptorMatch.weakMerchant;
  }
  if (aTokens.length == 1 || bTokens.length == 1) {
    return TransactionDescriptorMatch.strong;
  }

  final overlap = aTokens.toSet().intersection(bTokens.toSet()).length;
  final smaller = aTokens.length < bTokens.length
      ? aTokens.length
      : bTokens.length;
  if (overlap / smaller >= 0.66) return TransactionDescriptorMatch.strong;
  return TransactionDescriptorMatch.weakMerchant;
}

String _normalizedDescription(String input) {
  final tokens = _tokenRun
      .allMatches(input.toLowerCase())
      .map((m) => m.group(0)!)
      .toList(growable: false);
  return tokens.join();
}

List<String> _descriptionTokens(String input) {
  final out = <String>[];
  for (final m in _tokenRun.allMatches(input.toLowerCase())) {
    final token = m.group(0)!;
    if (!_hasNamedChar.hasMatch(token)) continue;
    if (_isGeneric(token)) continue;
    out.add(token);
  }
  return out;
}

bool _isGeneric(String normalized) => _genericDescriptions.contains(normalized);
