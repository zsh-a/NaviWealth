import 'dart:convert';

import '../domain/hlc.dart';

/// Kind of state transition recorded by the audit ledger.
///
/// Closed enum: every value maps 1:1 to the `event_kind` CHECK constraint
/// on `domain_event_log`. Adding a new kind is a schema change.
enum DomainEventKind {
  /// Entity row was just inserted. `before_json` is NULL; `after_json`
  /// carries the full column set so the timeline can show "the row was
  /// created with these values."
  created,

  /// One or more columns of an existing row were updated. `before_json`
  /// and `after_json` each carry only the *changed* fields, matching the
  /// `fields_diff` granularity that flows through the sync OpLog.
  fieldChanged,

  /// The entity was soft-deleted (tombstoned). `before_json` carries the
  /// `deleted_at` value before the delete (typically `null`), `after_json`
  /// is NULL — the post-delete state is "gone".
  softDeleted,

  /// A previously soft-deleted entity was restored. Symmetric counterpart
  /// to [softDeleted].
  restored;

  /// Wire form persisted in the `event_kind` column.
  String get wire {
    switch (this) {
      case DomainEventKind.created:
        return 'created';
      case DomainEventKind.fieldChanged:
        return 'field_changed';
      case DomainEventKind.softDeleted:
        return 'soft_deleted';
      case DomainEventKind.restored:
        return 'restored';
    }
  }

  static DomainEventKind fromWire(String wire) {
    switch (wire) {
      case 'created':
        return DomainEventKind.created;
      case 'field_changed':
        return DomainEventKind.fieldChanged;
      case 'soft_deleted':
        return DomainEventKind.softDeleted;
      case 'restored':
        return DomainEventKind.restored;
    }
    throw FormatException('Unknown domain_event_log.event_kind: $wire');
  }
}

/// Read-side projection of a single `domain_event_log` row.
///
/// Holds the parsed `before` / `after` maps so callers don't repeat the
/// JSON decode. Equality / hash are deliberately not implemented:
/// rows are identified by their UUID `id` and consumers either render
/// or aggregate them — value-equality across two reconstructions has no
/// meaningful use case.
class DomainEvent {
  const DomainEvent({
    required this.id,
    required this.entityTable,
    required this.entityId,
    required this.kind,
    required this.actorUserId,
    required this.actorDeviceId,
    required this.recordedAt,
    required this.hlc,
    required this.before,
    required this.after,
    required this.reason,
  });

  final String id;
  final String entityTable;
  final String entityId;
  final DomainEventKind kind;
  final String actorUserId;
  final String actorDeviceId;
  final DateTime recordedAt;
  final Hlc hlc;

  /// Pre-change values for the fields in the diff. NULL for [DomainEventKind.created].
  final Map<String, Object?>? before;

  /// Post-change values for the fields in the diff. NULL for [DomainEventKind.softDeleted].
  final Map<String, Object?>? after;

  /// Caller-supplied rationale (e.g. "对账修正"). Free-form, never required.
  final String? reason;
}

/// Serialise a field map (Decimals already stringified by callers, dates
/// as RFC3339 UTC, etc.) into the canonical event-log JSON form.
String? encodeEventFields(Map<String, Object?>? fields) {
  if (fields == null) return null;
  return jsonEncode(fields);
}

/// Counterpart to [encodeEventFields]; returns `null` for both null and
/// empty inputs so callers can render "no diff" without an extra check.
Map<String, Object?>? decodeEventFields(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException(
      'domain_event_log JSON column must encode a JSON object',
    );
  }
  return decoded.map((k, v) => MapEntry(k as String, v));
}
