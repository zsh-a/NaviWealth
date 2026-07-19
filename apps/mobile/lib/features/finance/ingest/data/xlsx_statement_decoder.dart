library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

const int _maxExpandedPartBytes = 16 * 1024 * 1024;

/// Converts the first worksheet of an XLSX statement into RFC 4180 CSV.
///
/// The result reuses the deterministic statement parser. Only the workbook
/// parts needed for cell values are expanded, with a strict decompressed-size
/// ceiling so a small ZIP cannot force unbounded memory use.
String decodeXlsxStatement(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final sharedStrings = _readSharedStrings(archive);
  final sheet = _requiredPart(archive, 'xl/worksheets/sheet1.xml');
  final document = XmlDocument.parse(utf8.decode(sheet));
  final output = StringBuffer();

  for (final row in document.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == 'row',
  )) {
    final values = <int, String>{};
    var maxColumn = -1;
    for (final cell in row.childElements.where(
      (element) => element.name.local == 'c',
    )) {
      final reference = cell.getAttribute('r');
      final column = reference == null ? maxColumn + 1 : _columnOf(reference);
      final type = cell.getAttribute('t');
      final rawValue = _cellValue(cell);
      final value = switch (type) {
        's' => _sharedString(rawValue, sharedStrings),
        'b' => rawValue == '1' ? 'TRUE' : 'FALSE',
        _ => rawValue,
      };
      values[column] = value;
      if (column > maxColumn) maxColumn = column;
    }
    if (maxColumn < 0) continue;
    output.writeln(
      [
        for (var column = 0; column <= maxColumn; column++)
          _escapeCsv(values[column] ?? ''),
      ].join(','),
    );
  }
  return output.toString();
}

List<String> _readSharedStrings(Archive archive) {
  final part = archive.findFile('xl/sharedStrings.xml');
  if (part == null) return const <String>[];
  final bytes = _partBytes(part);
  final document = XmlDocument.parse(utf8.decode(bytes));
  return [
    for (final item in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'si',
    ))
      item.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 't')
          .map((element) => element.innerText)
          .join(),
  ];
}

Uint8List _requiredPart(Archive archive, String name) {
  final part = archive.findFile(name);
  if (part == null) throw const FormatException('Missing worksheet');
  return _partBytes(part);
}

Uint8List _partBytes(ArchiveFile part) {
  if (part.size > _maxExpandedPartBytes) {
    throw const FormatException('Workbook part is too large');
  }
  final bytes = part.readBytes();
  if (bytes == null || bytes.length > _maxExpandedPartBytes) {
    throw const FormatException('Unreadable workbook part');
  }
  return bytes;
}

String _cellValue(XmlElement cell) {
  if (cell.getAttribute('t') == 'inlineStr') {
    return cell.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 't')
        .map((element) => element.innerText)
        .join();
  }
  for (final child in cell.childElements) {
    if (child.name.local == 'v') return child.innerText;
  }
  return '';
}

String _sharedString(String raw, List<String> values) {
  final index = int.tryParse(raw);
  if (index == null || index < 0 || index >= values.length) {
    throw const FormatException('Invalid shared string index');
  }
  return values[index];
}

int _columnOf(String reference) {
  var value = 0;
  var found = false;
  for (final codeUnit in reference.codeUnits) {
    if (codeUnit < 65 || codeUnit > 90) break;
    value = value * 26 + codeUnit - 64;
    found = true;
  }
  if (!found) throw const FormatException('Invalid cell reference');
  return value - 1;
}

String _escapeCsv(String value) {
  if (!value.contains(RegExp('[,"\\r\\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}
