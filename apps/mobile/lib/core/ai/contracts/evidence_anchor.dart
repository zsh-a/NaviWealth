/// Evidence anchor — a stable reference from a tool result back to the
/// local entity it was derived from. See `docs/ai/ai-protocol.md`.
///
/// Tools that return analytical aggregates (anomalies, breakdowns,
/// duplicate charges, …) emit an `evidence` field alongside their
/// result. The chat UI renders each anchor as a chip that deep-links to
/// the entity (`postings/<id>`, `assets/<id>`, …). This lets the user
/// verify "where did this number come from?" in one tap instead of
/// trusting the model's summary.
///
/// The shape stays narrow on purpose. Adding free-form metadata invites
/// drift; the UI deep-link target is the `entity_table` + `entity_id`
/// pair only.
library;

import 'source_identity.dart';

/// One reference from a tool result back to the entity it cited.
class EvidenceAnchor {
  const EvidenceAnchor({
    required this.entityTable,
    required this.entityId,
    this.label,
    this.sourceIdentity,
  });

  factory EvidenceAnchor.fromSource(SourceIdentity source, {String? label}) {
    final separator = source.rowFamily.indexOf(':');
    final entityTable = separator < 0
        ? source.rowFamily
        : source.rowFamily.substring(separator + 1);
    return EvidenceAnchor(
      entityTable: entityTable,
      entityId: source.rowId,
      label: label,
      sourceIdentity: source,
    );
  }

  /// Drift table name — `postings`, `assets`, `journal_entries`,
  /// `accounts`, etc. Used to dispatch to the right detail page.
  final String entityTable;

  /// Stable row id within [entityTable].
  final String entityId;

  /// Optional human label the UI surfaces on the chip (e.g. "餐饮支出
  /// 2026-05-12"). Falls back to the entity id when the page isn't
  /// available to resolve the label cheaply.
  final String? label;

  /// Typed identity used by Event/Agent evidence. Legacy tool anchors may
  /// leave this null and continue to route by [entityTable] + [entityId].
  final SourceIdentity? sourceIdentity;

  Map<String, Object?> toJson() => <String, Object?>{
    'entity_table': entityTable,
    'entity_id': entityId,
    if (label != null) 'label': label,
    if (sourceIdentity != null) 'source_identity': sourceIdentity!.toJson(),
  };

  factory EvidenceAnchor.fromJson(Map<String, Object?> json) {
    final sourceJson = json['source_identity'];
    return EvidenceAnchor(
      entityTable: json['entity_table'] as String? ?? '',
      entityId: json['entity_id'] as String? ?? '',
      label: json['label'] as String?,
      sourceIdentity: sourceJson is Map
          ? SourceIdentity.fromJson(sourceJson.cast<String, Object?>())
          : null,
    );
  }
}

/// Compose a tool result envelope that pairs [result] with a list of
/// [EvidenceAnchor]s. Returns a stable map shape so consumers can rely
/// on `output['evidence']` being a list (possibly empty) without nullable
/// branching.
///
/// Tools without evidence to surface should not call this — emit the
/// bare result. The presence of an `evidence` key is itself the signal
/// that the UI should render anchor chips.
Map<String, Object?> withEvidence({
  required Map<String, Object?> result,
  required Iterable<EvidenceAnchor> anchors,
}) {
  final list = anchors.toList(growable: false);
  return <String, Object?>{
    ...result,
    'evidence': [for (final a in list) a.toJson()],
  };
}

/// Inverse of [withEvidence]. Returns an empty list when the envelope
/// has no `evidence` field or the field has an unexpected shape — the
/// UI must tolerate both legacy outputs (no evidence) and partially
/// parsed model replies.
List<EvidenceAnchor> readEvidence(Map<String, Object?> envelope) {
  final raw = envelope['evidence'];
  if (raw is! List) return const [];
  final out = <EvidenceAnchor>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final cast = entry.cast<String, Object?>();
    final table = cast['entity_table'];
    final id = cast['entity_id'];
    if (table is! String || table.isEmpty) continue;
    if (id is! String || id.isEmpty) continue;
    out.add(EvidenceAnchor.fromJson(cast));
  }
  return out;
}
