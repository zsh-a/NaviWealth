part of 'bank_ingest_parser.dart';

({int index, List<String> cells})? _findBankHeader(
  List<String> lines,
  String delimiter,
) {
  for (var i = 0; i < lines.length; i++) {
    final cells = splitIngestRow(lines[i], delimiter);
    if (_headerMapping(cells) != null) return (index: i, cells: cells);
  }
  return null;
}

bool _shouldSkipByStatus(String? status) {
  if (status == null || status.isEmpty) return false;
  final normalized = normalizeIngestText(status);
  return normalized.contains('失败') ||
      normalized.contains('关闭') ||
      normalized.contains('撤销') ||
      normalized.contains('取消') ||
      normalized.contains('退款') ||
      normalized.contains('reversed') ||
      normalized.contains('cancelled') ||
      normalized.contains('failed');
}
