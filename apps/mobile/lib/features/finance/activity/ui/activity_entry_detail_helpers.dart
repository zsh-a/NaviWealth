part of 'activity_entry_detail_page.dart';

Posting? _headlinePosting(
  List<Posting> postings,
  Map<String, Account> accounts,
) {
  Posting? headline;
  Decimal? best;
  Posting? fallback;
  Decimal? fallbackBest;
  for (final p in postings) {
    final magnitude = p.units.abs();
    if (fallbackBest == null || magnitude > fallbackBest) {
      fallbackBest = magnitude;
      fallback = p;
    }

    final account = accounts[p.accountId];
    if (account == null) continue;
    if (account.category != AccountSide.asset &&
        account.category != AccountSide.liability) {
      continue;
    }
    if (best == null || magnitude > best) {
      best = magnitude;
      headline = p;
    }
  }
  return headline ?? fallback;
}

IconData _iconForKind(EntryKind kind) {
  switch (kind) {
    case EntryKind.income:
      return FLucideIcons.arrowDownLeft;
    case EntryKind.expense:
      return FLucideIcons.shoppingBag;
    case EntryKind.payment:
      return FLucideIcons.banknote;
    case EntryKind.transfer:
      return FLucideIcons.arrowLeftRight;
    case EntryKind.trade:
      return FLucideIcons.chartLine;
    case EntryKind.adjustment:
      return FLucideIcons.slidersHorizontal;
    case EntryKind.opening:
      return FLucideIcons.flag;
    case EntryKind.other:
      return FLucideIcons.receipt;
  }
}

Color _tintForKind(EntryKind kind, FColors colors, SemanticColors semantic) {
  switch (kind) {
    case EntryKind.income:
    case EntryKind.trade:
      return colors.primary;
    case EntryKind.expense:
    case EntryKind.payment:
      return semantic.danger;
    case EntryKind.transfer:
      return semantic.info;
    case EntryKind.adjustment:
      return semantic.warning;
    case EntryKind.opening:
    case EntryKind.other:
      return colors.mutedForeground;
  }
}

String _costLabel(Cost cost) {
  final lot = cost.lotId;
  final base = '{${_format(cost.perUnit)} ${cost.currency}}';
  return lot == null ? base : '$base $lot';
}

String _format(Decimal value) {
  if (value == Decimal.zero) return '0';
  final text = value.toString();
  if (!text.contains('.')) return text;
  final trimmed = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}

/// Strip the `market:` prefix from an asset unit ID so the UI shows
/// `AAPL` instead of `usStock:AAPL`.
String _displayUnit(String unit) {
  final colon = unit.indexOf(':');
  return colon >= 0 ? unit.substring(colon + 1) : unit;
}

Map<String, Decimal> _computeUnitTotals(List<Posting> postings) {
  final totals = <String, Decimal>{};
  for (final posting in postings) {
    totals.update(
      posting.unit,
      (existing) => existing + posting.units,
      ifAbsent: () => posting.units,
    );
  }
  totals.removeWhere((_, value) => value == Decimal.zero);
  return totals;
}
