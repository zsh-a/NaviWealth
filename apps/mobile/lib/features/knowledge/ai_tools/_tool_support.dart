/// Shared helpers across KnowledgeOS device tools
/// (`docs/domains/knowledgeos-domain.md` §4).
///
/// Keeps each tool file focused on schema + payload shaping instead of
/// re-deriving the proposal-envelope shape, the `bad_request` / `not_found`
/// result bodies, and the note-preview truncation in every file. Envelope
/// and error helpers delegate to `core/ai/composition/proposal_envelope.dart`
/// so FinanceOS and KnowledgeOS share the same outer wire contract.
library;

import '../../../core/ai/composition/proposal_envelope.dart'
    as proposal_envelope;
import '../domain/knowledge_text.dart';

const String kProposalConfirmNote = proposal_envelope.kProposalConfirmNote;

/// Cross-domain `propose_*` envelope shape (matches the finance proposal
/// contract). Pass [note] to name the concrete repository call a tool
/// commits to; otherwise the generic [kProposalConfirmNote] is used.
Map<String, Object?> proposalEnvelope({
  required String kind,
  required String summaryZh,
  required Map<String, Object?> payload,
  String note = kProposalConfirmNote,
}) => proposal_envelope.readyPlan(
  kind: kind,
  summaryZh: summaryZh,
  payload: payload,
  note: note,
);

/// KnowledgeOS-specific terminal envelope for captures that should remain
/// plain notes. It deliberately does not parse into a confirmable
/// [ProposalPlan].
Map<String, Object?> noUpgradeEnvelope({
  required String summaryZh,
  required Map<String, Object?> payload,
  required String note,
}) => <String, Object?>{
  'proposal_id': proposal_envelope.proposalNewId(),
  'kind': 'capture_no_upgrade',
  'status': 'no_upgrade',
  'summary_zh': summaryZh,
  'payload': payload,
  'note': note,
};

/// Standard `bad_request` tool result. Returned (not thrown) so the agent
/// loop relays the message back to the model.
Map<String, Object?> badRequest(String message) =>
    proposal_envelope.proposalBadRequest(message);

/// Standard `not_found` tool result carrying the offending [missing] ids.
Map<String, Object?> notFound(String message, List<String> missing) =>
    proposal_envelope.proposalNotFound(message, missing);

/// Short label for a note in a proposal summary: prefer the title, else a
/// truncated body, else a placeholder. Shared by the inbox `propose_*`
/// trio (was `_preview` / `_titlePreview` duplicated per file).
String notePreview(
  String title,
  String body, {
  int max = kKnowledgeInlineExcerptMaxChars,
}) {
  if (title.isNotEmpty) return title;
  if (body.isEmpty) return '(untitled)';
  return knowledgeExcerpt(body, max: max);
}
