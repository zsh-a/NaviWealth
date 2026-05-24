/// §5.10.10 / S5a — the on-device deterministic statement parser.
///
/// No network, no LLM: a pasted CSV / TSV statement is turned into
/// [ParsedTransaction]s by pure string work. This is the "device-first,
/// 云端仅在必要时" rule in practice — the cloud Vision path (S5b) only
/// exists for inputs this parser structurally cannot read (images/PDF).
library;

import 'package:decimal/decimal.dart';

import '../domain/ingest_models.dart';

/// Header tokens (lower-cased, CJK included) that map a column to a role.
const Map<String, _Col> _headerAliases = <String, _Col>{
  'date': _Col.date,
  '日期': _Col.date,
  '交易日期': _Col.date,
  'time': _Col.date,
  'description': _Col.description,
  'desc': _Col.description,
  'narration': _Col.description,
  '摘要': _Col.description,
  '备注': _Col.description,
  '描述': _Col.description,
  'payee': _Col.payee,
  'merchant': _Col.payee,
  '商家': _Col.payee,
  '交易对方': _Col.payee,
  'amount': _Col.amount,
  '金额': _Col.amount,
  '发生额': _Col.amount,
  'currency': _Col.currency,
  '货币': _Col.currency,
  '币种': _Col.currency,
};

enum _Col { date, description, payee, amount, currency }

/// Parse a CSV/TSV ledger dump. Rows that don't yield a valid date *and*
/// amount are skipped (never guessed) — a partial parse beats a wrong one.
/// [defaultCurrency] is used when the row carries no currency column.
List<ParsedTransaction> parseCsvLedger(
  String raw, {
  String defaultCurrency = 'CNY',
}) {
  final lines = raw
      .split(RegExp(r'\r\n|\r|\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return const <ParsedTransaction>[];

  final delimiter = _detectDelimiter(lines.first);
  final firstCells = _splitRow(lines.first, delimiter);
  final mapping = _headerMapping(firstCells);
  final dataStart = mapping != null ? 1 : 0;
  // Positional fallback when there is no recognisable header:
  // date, description, amount, [currency].
  final effective =
      mapping ??
      <int, _Col>{
        0: _Col.date,
        1: _Col.description,
        2: _Col.amount,
        3: _Col.currency,
      };

  final out = <ParsedTransaction>[];
  for (var i = dataStart; i < lines.length; i++) {
    final cells = _splitRow(lines[i], delimiter);
    final txn = _rowToTransaction(cells, effective, defaultCurrency);
    if (txn != null) out.add(txn);
  }
  return out;
}

String _detectDelimiter(String headerLine) {
  if (headerLine.contains('\t')) return '\t';
  if (headerLine.contains(';') && !headerLine.contains(',')) return ';';
  return ',';
}

List<String> _splitRow(String line, String delimiter) {
  // Minimal RFC-4180-ish handling: respect double-quoted fields so a
  // memo containing the delimiter doesn't shift columns.
  final cells = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == delimiter && !inQuotes) {
      cells.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  cells.add(buf.toString().trim());
  return cells;
}

Map<int, _Col>? _headerMapping(List<String> cells) {
  final mapping = <int, _Col>{};
  for (var i = 0; i < cells.length; i++) {
    final key = cells[i].toLowerCase().replaceAll('"', '').trim();
    final col = _headerAliases[key];
    if (col != null) mapping[i] = col;
  }
  // A header is only a header if it pins at least date + amount.
  if (mapping.values.contains(_Col.date) &&
      mapping.values.contains(_Col.amount)) {
    return mapping;
  }
  return null;
}

ParsedTransaction? _rowToTransaction(
  List<String> cells,
  Map<int, _Col> mapping,
  String defaultCurrency,
) {
  String? cell(_Col c) {
    for (final e in mapping.entries) {
      if (e.value == c && e.key < cells.length) {
        final v = cells[e.key].trim();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  final date = _parseDate(cell(_Col.date));
  if (date == null) return null;

  final minor = _parseAmountMinor(cell(_Col.amount));
  if (minor == null || minor == 0) return null;

  final payee = cell(_Col.payee);
  final desc = cell(_Col.description);
  final description = [
    payee,
    desc,
  ].where((s) => s != null && s.isNotEmpty).join(' · ');

  final currency = (cell(_Col.currency) ?? defaultCurrency)
      .toUpperCase()
      .trim();

  return ParsedTransaction(
    // S5a only produces expenses; normalise to the negative-outflow
    // convention regardless of how the bank signed the column.
    description: description.isEmpty ? '未命名交易' : description,
    amountMinor: -minor.abs(),
    currency: currency.isEmpty ? defaultCurrency : currency,
    occurredAt: date,
  );
}

DateTime? _parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return DateTime.utc(iso.year, iso.month, iso.day);

  final m = RegExp(
    r'^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})',
  ).firstMatch(s.trim());
  if (m == null) return null;
  final a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  final c = int.parse(m.group(3)!);
  // yyyy-mm-dd when the first group is a 4-digit year, else mm/dd/yyyy.
  final int y;
  final int mo;
  final int d;
  if (a > 31) {
    y = a;
    mo = b;
    d = c;
  } else {
    y = c < 100 ? 2000 + c : c;
    mo = a;
    d = b;
  }
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime.utc(y, mo, d);
}

int? _parseAmountMinor(String? s) {
  if (s == null || s.isEmpty) return null;
  var t = s.trim();
  final negative = t.startsWith('-') || (t.startsWith('(') && t.endsWith(')'));
  // Drop currency glyphs / letters / spaces / parens, keep digits, sign,
  // separators. Then treat comma as a thousands separator.
  t = t.replaceAll(RegExp(r'[^\d.,-]'), '');
  if (t.contains(',') && t.contains('.')) {
    t = t.replaceAll(',', '');
  } else if (t.contains(',') && !t.contains('.')) {
    // Ambiguous "1,234" → thousands; "1,23" (rare) also → drop comma.
    t = t.replaceAll(',', '');
  }
  t = t.replaceAll(RegExp(r'(?!^)-'), '');
  final dec = Decimal.tryParse(t.replaceAll('-', ''));
  if (dec == null) return null;
  final minor = (dec * Decimal.fromInt(100)).round().toBigInt().toInt();
  return negative ? -minor : minor;
}
