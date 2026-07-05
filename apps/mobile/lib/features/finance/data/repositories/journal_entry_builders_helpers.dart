part of 'journal_entry_builders.dart';

void _assertPositive(Decimal value, String name) {
  if (value <= Decimal.zero) {
    throw ArgumentError.value(value, name, 'must be > 0');
  }
}

/// Returns [amount] when both [amount] and [accountId] are present,
/// `null` when both are absent, throws if exactly one is supplied.
/// Keeps the per-event `feeAmount` / `feeAccountId` etc. couplings
/// honest at the call site.
Decimal? _normalizeOptionalAmount(
  Decimal? amount,
  String? accountId, {
  required String label,
}) {
  if (amount == null && accountId == null) return null;
  if (amount == null || accountId == null) {
    throw ArgumentError(
      '$label requires both amount and accountId, or neither',
    );
  }
  if (amount <= Decimal.zero) {
    throw ArgumentError.value(amount, '${label}Amount', 'must be > 0');
  }
  return amount;
}

List<String> _withAssetTag(List<String> tagIds, String assetUnit) {
  final tag = 'asset:$assetUnit';
  if (tagIds.contains(tag)) return tagIds;
  return <String>[...tagIds, tag];
}

String _defaultBuyNarration(Decimal qty, String unit) =>
    'Buy ${_trim(qty)} ${_displayUnit(unit)}';

String _defaultSellNarration(Decimal qty, String unit) =>
    'Sell ${_trim(qty)} ${_displayUnit(unit)}';

/// Strip the `market:` prefix from an asset unit ID so the narration
/// shows `AAPL` instead of `usStock:AAPL`.
String _displayUnit(String unit) {
  final colon = unit.indexOf(':');
  return colon >= 0 ? unit.substring(colon + 1) : unit;
}

String _trim(Decimal v) {
  final s = v.toString();
  if (!s.contains('.')) return s;
  final trimmed = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}
