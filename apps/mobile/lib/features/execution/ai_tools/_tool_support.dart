/// ExecutionOS device-tool payload shaping helpers.
///
/// Envelope and error wrappers delegate to
/// `core/ai/composition/proposal_tool_support.dart`. Only ExecutionOS-specific
/// payload shaping lives here.
library;

export '../../../core/ai/composition/proposal_tool_support.dart'
    show badRequest, proposalEnvelope;

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
