part of 'activity_entry_detail_page.dart';

Posting? _headlinePosting(
  List<Posting> postings,
  Map<String, Account> accounts,
) {
  return activityHeadlinePosting(postings, accounts);
}

IconData _iconForKind(EntryKind kind) => activityKindIcon(kind);

Color _tintForKind(EntryKind kind, FColors colors, AppStatus status) {
  return activityKindTint(kind, colors, status);
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
