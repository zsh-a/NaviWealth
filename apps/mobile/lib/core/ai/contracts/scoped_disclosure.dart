/// Cloud-initiated, user-consented drill-down into ledger detail.
///
/// The default privacy posture is 'aggregate only': [ContextPack]
/// carries summaries, never raw rows. When the cloud planner needs
/// detail to answer a question, it emits a [DisclosureRequest] as a
/// tool call. The device PrivacyGate surfaces consent UI (or auto-
/// allows under session policy), pulls the rows from Drift, anonymises
/// them per [AnonymizationLevel], and replies with a
/// [DisclosureResponse].
///
/// Disclosure responses **must not** be persisted on the device — they
/// live only for the duration of the SSE stream and are summarised
/// into [AiTrace] for audit. The cloud likewise treats disclosure rows
/// as non-cacheable.
library;

import 'privacy_budget.dart' show AnonymizationLevel, AnonymizationLevelWire;
import 'task_context.dart' show DateRange;

enum DisclosurePurpose {
  drillDownExpense,
  drillDownInvestment,
  refundMatching,
  anomalyExplain,
  recurringDetect,
  other,
}

extension DisclosurePurposeWire on DisclosurePurpose {
  String get wire => switch (this) {
    DisclosurePurpose.drillDownExpense => 'drill_down_expense',
    DisclosurePurpose.drillDownInvestment => 'drill_down_investment',
    DisclosurePurpose.refundMatching => 'refund_matching',
    DisclosurePurpose.anomalyExplain => 'anomaly_explain',
    DisclosurePurpose.recurringDetect => 'recurring_detect',
    DisclosurePurpose.other => 'other',
  };

  static DisclosurePurpose parse(String s) => switch (s) {
    'drill_down_expense' => DisclosurePurpose.drillDownExpense,
    'drill_down_investment' => DisclosurePurpose.drillDownInvestment,
    'refund_matching' => DisclosurePurpose.refundMatching,
    'anomaly_explain' => DisclosurePurpose.anomalyExplain,
    'recurring_detect' => DisclosurePurpose.recurringDetect,
    _ => DisclosurePurpose.other,
  };
}

/// Whitelist of fields the cloud may request via [DisclosureRequest].
/// Anything not in this enum is unconditionally rejected by the device
/// PrivacyGate. Adding a field requires a deliberate code change (and
/// ideally a [ContextPackVersion] minor bump).
enum LedgerField {
  amount,
  currency,
  date,
  category,
  /// Coarse account kind ('cash', 'deposit', ...) — never the name.
  accountKind,
  /// Hashed merchant token only. Raw merchant name is never disclosable.
  merchantHashed,
  note,
  tagIds,
  recurringPatternId,
  refundLinkId,
}

extension LedgerFieldWire on LedgerField {
  String get wire => switch (this) {
    LedgerField.amount => 'amount',
    LedgerField.currency => 'currency',
    LedgerField.date => 'date',
    LedgerField.category => 'category',
    LedgerField.accountKind => 'account_kind',
    LedgerField.merchantHashed => 'merchant_hashed',
    LedgerField.note => 'note',
    LedgerField.tagIds => 'tag_ids',
    LedgerField.recurringPatternId => 'recurring_pattern_id',
    LedgerField.refundLinkId => 'refund_link_id',
  };

  static LedgerField? tryParse(String s) => switch (s) {
    'amount' => LedgerField.amount,
    'currency' => LedgerField.currency,
    'date' => LedgerField.date,
    'category' => LedgerField.category,
    'account_kind' => LedgerField.accountKind,
    'merchant_hashed' => LedgerField.merchantHashed,
    'note' => LedgerField.note,
    'tag_ids' => LedgerField.tagIds,
    'recurring_pattern_id' => LedgerField.recurringPatternId,
    'refund_link_id' => LedgerField.refundLinkId,
    _ => null,
  };
}

class DisclosureRequest {
  const DisclosureRequest({
    required this.requestId,
    required this.purpose,
    required this.fields,
    required this.range,
    required this.maxRows,
    required this.anonymization,
    required this.humanReasonZh,
  });

  final String requestId;
  final DisclosurePurpose purpose;
  final List<LedgerField> fields;
  final DateRange range;
  final int maxRows;
  final AnonymizationLevel anonymization;

  /// One-sentence human-readable reason shown in the consent UI.
  /// Locale-aware copy is the device's responsibility; this field
  /// carries the cloud's best-effort default.
  final String humanReasonZh;

  Map<String, Object?> toJson() => <String, Object?>{
    'request_id': requestId,
    'purpose': purpose.wire,
    'fields': fields.map((f) => f.wire).toList(growable: false),
    'range': range.toJson(),
    'max_rows': maxRows,
    'anonymization': anonymization.wire,
    'human_reason_zh': humanReasonZh,
  };

  factory DisclosureRequest.fromJson(Map<String, Object?> json) {
    final id = json['request_id'];
    final p = json['purpose'];
    final fieldsRaw = json['fields'];
    final fields = <LedgerField>[];
    if (fieldsRaw is List) {
      for (final e in fieldsRaw) {
        if (e is String) {
          final parsed = LedgerFieldWire.tryParse(e);
          if (parsed != null) fields.add(parsed);
        }
      }
    }
    final rng = json['range'];
    final mr = json['max_rows'];
    final an = json['anonymization'];
    final hr = json['human_reason_zh'];
    return DisclosureRequest(
      requestId: id is String ? id : '',
      purpose: p is String
          ? DisclosurePurposeWire.parse(p)
          : DisclosurePurpose.other,
      fields: fields,
      range: rng is Map
          ? DateRange.fromJson(_strKeyed(rng))
          : const DateRange(
              fromInclusive: '1970-01-01',
              toExclusive: '1970-01-01',
            ),
      maxRows: mr is int ? mr : 0,
      anonymization: an is String
          ? AnonymizationLevelWire.parse(an)
          : AnonymizationLevel.redact,
      humanReasonZh: hr is String ? hr : '',
    );
  }
}

enum UserConsent { oneTime, session, denied }

extension UserConsentWire on UserConsent {
  String get wire => switch (this) {
    UserConsent.oneTime => 'one_time',
    UserConsent.session => 'session',
    UserConsent.denied => 'denied',
  };

  static UserConsent parse(String s) => switch (s) {
    'one_time' => UserConsent.oneTime,
    'session' => UserConsent.session,
    'denied' => UserConsent.denied,
    _ => UserConsent.denied,
  };
}

class DisclosureResponse {
  const DisclosureResponse({
    required this.requestId,
    required this.consent,
    this.rows = const <Map<String, Object?>>[],
    this.truncatedFrom,
  });

  final String requestId;
  final UserConsent consent;
  final List<Map<String, Object?>> rows;

  /// Original row count before [DisclosureRequest.maxRows] truncation.
  /// Surfaced so the planner knows when its drill-down hit the cap and
  /// may need to narrow the range. `null` when no truncation occurred.
  final int? truncatedFrom;

  Map<String, Object?> toJson() => <String, Object?>{
    'request_id': requestId,
    'consent': consent.wire,
    'rows': rows,
    if (truncatedFrom != null) 'truncated_from': truncatedFrom,
  };

  factory DisclosureResponse.fromJson(Map<String, Object?> json) {
    final id = json['request_id'];
    final c = json['consent'];
    final rs = json['rows'];
    final tf = json['truncated_from'];
    final rows = <Map<String, Object?>>[];
    if (rs is List) {
      for (final r in rs) {
        if (r is Map) {
          rows.add(_strKeyed(r));
        }
      }
    }
    return DisclosureResponse(
      requestId: id is String ? id : '',
      consent: c is String ? UserConsentWire.parse(c) : UserConsent.denied,
      rows: rows,
      truncatedFrom: tf is int ? tf : null,
    );
  }
}

Map<String, Object?> _strKeyed(Map<Object?, Object?> raw) =>
    raw.map((k, v) => MapEntry(k.toString(), v));
