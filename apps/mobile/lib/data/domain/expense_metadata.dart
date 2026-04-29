import 'dart:convert';

/// FIR-68 — typed view over the `expense_metadata_json` blob stored on
/// `transactions` rows whose `type = expense`.
///
/// We keep this off the wide-row Transactions table for the same reason
/// FIR-44 stuffed deposit/wealth specifics into `assets.metadata_json`:
/// adding expense-only columns would bloat every transaction row, even
/// though the vast majority are buys/sells with no expense data.
///
/// Sync semantics: a partial edit (e.g. recategorising) ships
/// `expense_metadata_json` as a single field in the Op `fields_diff`.
/// That's row-level LWW *within* the blob, which is fine for v1 — the
/// inner fields only race when the user is actively editing the same
/// expense from two devices simultaneously.
class ExpenseMetadata {
  const ExpenseMetadata({required this.categoryId, this.tags = const []});

  /// FK into `expense_categories.id`. Required — every expense must be
  /// classified, even if it lands in the catch-all "其它" bucket.
  final String categoryId;

  /// Free-form labels. Distinct from the category tree because tags are
  /// flat / multi-select and meant for ad-hoc analysis ("travel-japan-2026"),
  /// while categories are the canonical reporting buckets.
  final List<String> tags;

  ExpenseMetadata copyWith({String? categoryId, List<String>? tags}) =>
      ExpenseMetadata(
        categoryId: categoryId ?? this.categoryId,
        tags: tags ?? this.tags,
      );

  Map<String, Object?> toJson() => {
    'category_id': categoryId,
    if (tags.isNotEmpty) 'tags': tags,
  };

  String encode() => jsonEncode(toJson());

  /// Returns `null` for null / empty / structurally invalid blobs (e.g. a
  /// JSON string instead of an object, or an object missing `category_id`).
  /// Throws [FormatException] when the input isn't valid JSON at all —
  /// that's a corruption signal worth surfacing rather than silently
  /// dropping.
  static ExpenseMetadata? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    final raw = jsonDecode(json);
    if (raw is! Map) return null;
    final map = raw.map((k, v) => MapEntry(k as String, v));
    final categoryId = map['category_id'];
    if (categoryId is! String) return null;
    final rawTags = map['tags'];
    final tags = rawTags is List
        ? rawTags.whereType<String>().toList(growable: false)
        : const <String>[];
    return ExpenseMetadata(categoryId: categoryId, tags: tags);
  }

  @override
  bool operator ==(Object other) =>
      other is ExpenseMetadata &&
      other.categoryId == categoryId &&
      _listEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(categoryId, Object.hashAll(tags));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
