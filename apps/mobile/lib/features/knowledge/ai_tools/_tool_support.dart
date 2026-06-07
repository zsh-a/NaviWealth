/// Shared helpers across KnowledgeOS device tools
/// (`docs/knowledgeos-domain.md` §4).
///
/// Keeps each tool file focused on schema + payload shaping instead of
/// re-deriving the proposal-envelope shape, the `bad_request` / `not_found`
/// result bodies, and the note-preview truncation in every file. These
/// were copy-pasted across ~6 `propose_*` tools and the inbox trio before
/// being collapsed here.
library;

import '../data/providers.dart' show kKnowledgeUuid;
import '../domain/knowledge_text.dart';

/// Default `note` carried on every KnowledgeOS proposal envelope: the UI
/// must surface `summary_zh` and only commit on explicit user confirmation
/// (northstar 行为契约 / ai-architecture.md).
const String kProposalConfirmNote =
    '前端必须显示 summary_zh 给用户确认；只有用户明确点确认后才走 Repository。';

/// Cross-domain `propose_*` envelope shape (matches the finance proposal
/// contract). Pass [note] to name the concrete repository call a tool
/// commits to; otherwise the generic [kProposalConfirmNote] is used.
Map<String, Object?> proposalEnvelope({
  required String kind,
  required String summaryZh,
  required Map<String, Object?> payload,
  String note = kProposalConfirmNote,
}) => <String, Object?>{
  'proposal_id': kKnowledgeUuid.v4(),
  'kind': kind,
  'status': 'ready',
  'summary_zh': summaryZh,
  'payload': payload,
  'warnings': const <String>[],
  'missing': const <String>[],
  'candidates': null,
  'note': note,
};

/// Standard `bad_request` tool result. Returned (not thrown) so the agent
/// loop relays the message back to the model.
Map<String, Object?> badRequest(String message) => <String, Object?>{
  'error': message,
  'code': 'bad_request',
};

/// Standard `not_found` tool result carrying the offending [missing] ids.
Map<String, Object?> notFound(String message, List<String> missing) =>
    <String, Object?>{
      'error': message,
      'code': 'not_found',
      'missing': missing,
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
