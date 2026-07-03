import 'package:decimal/decimal.dart';

String detectIngestDelimiter(List<String> lines) {
  final sample = lines.firstWhere(
    (line) => !isIngestPreambleLine(line),
    orElse: () => lines.first,
  );
  if (sample.contains('\t')) return '\t';
  if (sample.contains(';') && !sample.contains(',')) return ';';
  return ',';
}

bool isIngestPreambleLine(String line) {
  final text = line.trim();
  return text.isEmpty ||
      text.startsWith('#') ||
      text.startsWith('----------------');
}

List<String> splitIngestRow(String line, String delimiter) {
  final cells = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == delimiter && !inQuotes) {
      cells.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  cells.add(buffer.toString().trim());
  return cells;
}

DateTime? parseIngestDate(String? value, {bool allowChineseDate = true}) {
  if (value == null || value.isEmpty) return null;
  final cleaned = cleanIngestCell(value);
  final iso = DateTime.tryParse(cleaned);
  if (iso != null) return DateTime.utc(iso.year, iso.month, iso.day);

  if (allowChineseDate) {
    final chinese = RegExp(
      r'^(\d{4})年(\d{1,2})月(\d{1,2})日?',
    ).firstMatch(cleaned);
    if (chinese != null) {
      final year = int.parse(chinese.group(1)!);
      final month = int.parse(chinese.group(2)!);
      final day = int.parse(chinese.group(3)!);
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      return DateTime.utc(year, month, day);
    }
  }

  final match = RegExp(
    r'^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})',
  ).firstMatch(cleaned);
  if (match == null) return null;
  final a = int.parse(match.group(1)!);
  final b = int.parse(match.group(2)!);
  final c = int.parse(match.group(3)!);
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

int? parseIngestAmountMinor(String? value) {
  if (value == null || value.isEmpty) return null;
  var text = cleanIngestCell(value);
  if (text.isEmpty || text == '/' || text == '--' || text == '-') return null;
  final negative =
      text.startsWith('-') || (text.startsWith('(') && text.endsWith(')'));
  text = text.replaceAll(RegExp(r'[^\d.,-]'), '');
  if (text.contains(',')) text = text.replaceAll(',', '');
  text = text.replaceAll(RegExp(r'(?!^)-'), '');
  final decimal = Decimal.tryParse(text.replaceAll('-', ''));
  if (decimal == null) return null;
  final minor = (decimal * Decimal.fromInt(100)).round().toBigInt().toInt();
  return negative ? -minor : minor;
}

String normalizeIngestHeader(String value, {bool stripSlash = false}) {
  final separatorPattern = stripSlash
      ? RegExp(r'[\s_\-：:\/]+')
      : RegExp(r'[\s_\-：:]+');
  return cleanIngestCell(value)
      .toLowerCase()
      .replaceAll(separatorPattern, '')
      .replaceAll('（', '(')
      .replaceAll('）', ')');
}

String normalizeIngestText(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s_\-：:·,，/()（）&]+'), '');

String cleanIngestCell(String value) {
  var text = value
      .replaceAll('\ufeff', '')
      .replaceAll('\u200b', '')
      .replaceAll('"', '')
      .trim();
  while (text.startsWith('`') || text.startsWith('\'')) {
    text = text.substring(1).trimLeft();
  }
  return text;
}
