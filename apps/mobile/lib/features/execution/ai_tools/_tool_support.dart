import '../../../core/ai/composition/proposal_envelope.dart'
    as proposal_envelope;

Map<String, Object?> proposalEnvelope({
  required String kind,
  required String summaryZh,
  required Map<String, Object?> payload,
  String note = proposal_envelope.kProposalConfirmNote,
}) => proposal_envelope.readyPlan(
  kind: kind,
  summaryZh: summaryZh,
  payload: payload,
  note: note,
);

Map<String, Object?> badRequest(String message) =>
    proposal_envelope.proposalBadRequest(message);

String shortText(String value, {int max = 96}) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= max) return trimmed;
  return '${trimmed.substring(0, max - 1)}…';
}

DateTime? optionalIsoDate(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? DateTime.tryParse(raw) : null;

String? optionalString(Object? raw) {
  final value = raw is String ? raw.trim() : '';
  return value.isEmpty ? null : value;
}

void addOptionalString(Map<String, Object?> payload, String key, Object? raw) {
  final value = optionalString(raw);
  if (value != null) payload[key] = value;
}

void addSourceRefPayload(
  Map<String, Object?> payload,
  Map<String, Object?> input,
) {
  addOptionalString(payload, 'source_domain', input['source_domain']);
  addOptionalString(payload, 'source_row_family', input['source_row_family']);
  addOptionalString(payload, 'source_row_id', input['source_row_id']);
  addOptionalString(payload, 'source_label', input['source_label']);
}
