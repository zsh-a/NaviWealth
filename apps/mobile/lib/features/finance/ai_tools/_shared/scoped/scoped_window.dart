/// Shared Scoped-Detail helpers (§4.6 W-D4.4) — Dart port of the
/// constants + parsing公约 in
/// `apps/backend/src/ai/read_models/scoped_detail/common.rs`.
///
/// **Two intentional device divergences** (§4.6.3 — device-direct data
/// never leaves the device):
///  1. **No HMAC** — `merchant_hashed` is dropped; the device returns a
///     real `note_excerpt` instead. Hashing only existed so raw fields
///     wouldn't egress to *our* cloud; that boundary doesn't apply.
///  2. The `journal_entries.payload.category` axis has no device
///     equivalent (the typed `JournalEntry` carries no category — on
///     device "category" *is* the expense account). Window tools emit
///     `category: null` and surface a `device_note` if a `category`
///     filter is supplied rather than silently returning wrong rows.
library;

const int kScopedMaxRangeDays = 31;
const int kScopedMaxLimit = 50;
const int kScopedDefaultLimit = 20;
const int kScopedNoteExcerptChars = 60;

/// `DisclosurePurpose` enum (verbatim from `is_known_purpose`).
const Set<String> kScopedPurposes = {
  'drill_down_expense',
  'drill_down_investment',
  'refund_matching',
  'anomaly_explain',
  'recurring_detect',
  'other',
};

bool isScopedPurpose(String s) => kScopedPurposes.contains(s);

/// Port of `common::parse_iso`: RFC3339, **or** a bare `YYYY-MM-DD`
/// pinned to that calendar day at 00:00 UTC (so a +08:00 device
/// doesn't shift the window edge a day, matching the backend).
DateTime? scopedParseIso(String s) {
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    final d = DateTime.tryParse(s);
    return d == null ? null : DateTime.utc(d.year, d.month, d.day);
  }
  return DateTime.tryParse(s)?.toUtc();
}

/// Port of `common::excerpt`.
String scopedExcerpt(String s, int maxChars) {
  final chars = s.runes.toList();
  if (chars.length <= maxChars) return s;
  return '${String.fromCharCodes(chars.take(maxChars))}…';
}

/// Port of `parse_limit`: clamp to 1..=[kScopedMaxLimit], default
/// [kScopedDefaultLimit].
int parseScopedLimit(Map<String, Object?> input) {
  final v = input['limit'];
  final n = v is num ? v.toInt() : null;
  if (n == null) return kScopedDefaultLimit;
  return n.clamp(1, kScopedMaxLimit);
}

/// Port of `validate_range` — null = ok, else the BadRequest message.
String? validateScopedRange(DateTime from, DateTime to) {
  if (!to.isAfter(from)) return 'to must be after from';
  if (to.difference(from).inDays > kScopedMaxRangeDays) {
    return 'range exceeds $kScopedMaxRangeDays days; '
        'narrow the window or call again';
  }
  return null;
}
