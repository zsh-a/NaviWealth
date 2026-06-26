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
