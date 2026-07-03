part of 'securities_search_service.dart';

class _MarketSymbolKey {
  const _MarketSymbolKey(this.market, this.symbolLower);

  final String market;
  final String symbolLower;

  @override
  bool operator ==(Object other) =>
      other is _MarketSymbolKey &&
      other.market == market &&
      other.symbolLower == symbolLower;

  @override
  int get hashCode => Object.hash(market, symbolLower);
}

/// Heuristic: does the query contain CJK characters? A character in the
/// CJK Unified Ideographs block (U+4E00–U+9FFF) is enough — we don't
/// need a full Unicode property table for the substring fallback.
bool _isCjk(String s) {
  for (final rune in s.runes) {
    if (rune >= 0x4E00 && rune <= 0x9FFF) return true;
  }
  return false;
}

/// Escape `%` and `_` (and the escape char itself) so a user query that
/// happens to contain `%foo%` doesn't widen the LIKE to a full table
/// scan. Pairs with the `ESCAPE '\\'` clause on each LIKE.
String _escapeLike(String s) {
  return s
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

/// Build a `List<Variable<Object>>` from a list of dart values for a
/// `customSelect` call. Drift exposes `Variable.withInt` /
/// `Variable.withString` etc. but no generic factory; this helper picks
/// the right typed factory per element so callers can stay readable.
List<Variable<Object>> _vars(List<Object?> args) {
  final out = <Variable<Object>>[];
  for (final v in args) {
    if (v == null) {
      // customSelect placeholders can't represent NULL — callers gate
      // null args with `if (...)` upstream, so reaching this branch is
      // a programming error worth surfacing rather than silently
      // dropping the param and shifting every later placeholder.
      throw ArgumentError('null variable in catalog search args');
    }
    if (v is int) {
      out.add(Variable.withInt(v));
    } else if (v is String) {
      out.add(Variable.withString(v));
    } else if (v is double) {
      out.add(Variable.withReal(v));
    } else if (v is bool) {
      out.add(Variable.withBool(v));
    } else {
      throw ArgumentError(
        'unsupported variable type ${v.runtimeType} in catalog search args',
      );
    }
  }
  return out;
}
