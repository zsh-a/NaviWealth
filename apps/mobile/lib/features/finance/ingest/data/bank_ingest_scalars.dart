part of 'bank_ingest_parser.dart';

String _detectDelimiter(List<String> lines) {
  final sample = lines.firstWhere(
    (l) => !_isPreambleLine(l),
    orElse: () => lines.first,
  );
  if (sample.contains('\t')) return '\t';
  if (sample.contains(';') && !sample.contains(',')) return ';';
  return ',';
}

({int index, List<String> cells})? _findBankHeader(
  List<String> lines,
  String delimiter,
) {
  for (var i = 0; i < lines.length; i++) {
    final cells = _splitRow(lines[i], delimiter);
    if (_headerMapping(cells) != null) return (index: i, cells: cells);
  }
  return null;
}

DateTime? _parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  final cleaned = _cleanCell(s);
  final iso = DateTime.tryParse(cleaned);
  if (iso != null) return DateTime.utc(iso.year, iso.month, iso.day);
  final cm = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日?').firstMatch(cleaned);
  if (cm != null) {
    final year = int.parse(cm.group(1)!);
    final month = int.parse(cm.group(2)!);
    final day = int.parse(cm.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime.utc(year, month, day);
  }
  final m = RegExp(
    r'^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})',
  ).firstMatch(cleaned);
  if (m == null) return null;
  final a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  final c = int.parse(m.group(3)!);
  final int year;
  final int month;
  final int day;
  if (a > 31) {
    year = a;
    month = b;
    day = c;
  } else {
    year = c < 100 ? 2000 + c : c;
    month = a;
    day = b;
  }
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime.utc(year, month, day);
}

int? _parseAmountMinor(String? s) {
  if (s == null || s.isEmpty) return null;
  var t = _cleanCell(s);
  if (t.isEmpty || t == '/' || t == '--' || t == '-') return null;
  final negative = t.startsWith('-') || (t.startsWith('(') && t.endsWith(')'));
  t = t.replaceAll(RegExp(r'[^\d.,-]'), '');
  if (t.contains(',')) t = t.replaceAll(',', '');
  t = t.replaceAll(RegExp(r'(?!^)-'), '');
  final dec = Decimal.tryParse(t.replaceAll('-', ''));
  if (dec == null) return null;
  final minor = (dec * Decimal.fromInt(100)).round().toBigInt().toInt();
  return negative ? -minor : minor;
}

List<String> _splitRow(String line, String delimiter) {
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

bool _isPreambleLine(String line) {
  final t = line.trim();
  return t.isEmpty || t.startsWith('#') || t.startsWith('----------------');
}

bool _shouldSkipByStatus(String? status) {
  if (status == null || status.isEmpty) return false;
  final normalized = _normalizeText(status);
  return normalized.contains('失败') ||
      normalized.contains('关闭') ||
      normalized.contains('撤销') ||
      normalized.contains('取消') ||
      normalized.contains('退款') ||
      normalized.contains('reversed') ||
      normalized.contains('cancelled') ||
      normalized.contains('failed');
}

String _normalizeHeader(String s) => _cleanCell(s)
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_\-：:\/]+'), '')
    .replaceAll('（', '(')
    .replaceAll('）', ')');

String _normalizeText(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[\s_\-：:·,，/()（）&]+'), '');

String _cleanCell(String s) {
  var t = s
      .replaceAll('\ufeff', '')
      .replaceAll('\u200b', '')
      .replaceAll('"', '')
      .trim();
  while (t.startsWith('`') || t.startsWith('\'')) {
    t = t.substring(1).trimLeft();
  }
  return t;
}
