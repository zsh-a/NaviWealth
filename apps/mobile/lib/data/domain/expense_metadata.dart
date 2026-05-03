import 'dart:convert';

/// Typed view over the `expense_metadata_json` blob stored on
/// expense journal entries.
///
/// Sync semantics: a partial edit (e.g. adding tags) ships
/// `expense_metadata_json` as a single field in the Op `fields_diff`.
/// That's row-level LWW *within* the blob, which is fine for v1.
class ExpenseMetadata {
  const ExpenseMetadata({this.tags = const []});

  /// Free-form labels. Distinct from expense accounts because tags are
  /// flat / multi-select and meant for ad-hoc analysis ("travel-japan-2026"),
  /// while accounts are the canonical reporting buckets.
  final List<String> tags;

  ExpenseMetadata copyWith({List<String>? tags}) =>
      ExpenseMetadata(tags: tags ?? this.tags);

  Map<String, Object?> toJson() => {
    if (tags.isNotEmpty) 'tags': tags,
  };

  String encode() => jsonEncode(toJson());

  /// Returns `null` for null / empty / structurally invalid blobs.
  /// Throws [FormatException] when the input isn't valid JSON at all —
  /// that's a corruption signal worth surfacing rather than silently
  /// dropping.
  static ExpenseMetadata? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    final raw = jsonDecode(json);
    if (raw is! Map) return null;
    final map = raw.map((k, v) => MapEntry(k as String, v));
    final rawTags = map['tags'];
    final tags = rawTags is List
        ? rawTags.whereType<String>().toList(growable: false)
        : const <String>[];
    return ExpenseMetadata(tags: tags);
  }

  @override
  bool operator ==(Object other) =>
      other is ExpenseMetadata && _listEquals(other.tags, tags);

  @override
  int get hashCode => Object.hashAll(tags);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
