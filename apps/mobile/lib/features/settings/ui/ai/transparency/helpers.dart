part of '../ai_transparency_page.dart';

Map<String, Object?>? _turnAttributes(AiTrace trace) {
  for (final span in trace.spans) {
    if (span.kind == AiSpanKind.turn) return span.attributes;
  }
  return null;
}

int? _intAttr(Map<String, Object?>? attrs, String key) {
  final value = attrs?[key];
  if (value is int) return value;
  if (value is num) return value.round();
  return null;
}

int _avg(List<int> sortedAsc) {
  if (sortedAsc.isEmpty) return 0;
  final total = sortedAsc.fold<int>(0, (sum, value) => sum + value);
  return (total / sortedAsc.length).round();
}

int _pctInts(List<int> sortedAsc, double q) {
  if (sortedAsc.isEmpty) return 0;
  final idx = ((sortedAsc.length - 1) * q).round();
  return sortedAsc[idx];
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)}KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
}

String _shortTimestamp(String iso) {
  if (iso.length < 16) return iso;
  return iso.substring(5, 16).replaceFirst('T', ' ');
}

String _longTimestamp(String iso) {
  if (iso.length < 19) return iso;
  return iso.substring(0, 19).replaceFirst('T', ' ');
}
