/// Shared helpers across KnowledgeOS device tools
/// (`docs/domains/knowledgeos-domain.md` §4).
///
/// Envelope and error wrappers delegate to
/// `core/ai/composition/proposal_tool_support.dart` so all domains share the
/// same outer wire contract. Only KnowledgeOS-specific payload shaping lives
/// here.
library;

import '../../../core/ai/composition/proposal_envelope.dart'
    as proposal_envelope;
import '../domain/knowledge_text.dart';

export '../../../core/ai/composition/proposal_tool_support.dart'
    show badRequest, kProposalConfirmNote, notFound, proposalEnvelope;

/// KnowledgeOS-specific terminal envelope for captures that should remain
/// plain notes. It deliberately does not parse into a confirmable
/// [proposal_envelope.readyPlan] shape.
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
