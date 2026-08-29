/// Shared device-tool wrappers on top of `proposal_envelope.dart`.
///
/// Every domain's `propose_*` tools need the same thin naming layer over the
/// stable envelope contract (`proposalEnvelope`, `badRequest`, `notFound`).
/// This file owns those wrappers once so each domain's `_tool_support.dart`
/// keeps only its own payload shaping. Domain-neutral payload shapers belong
/// here only once a second domain actually needs them.
library;

import 'proposal_envelope.dart';

export 'proposal_envelope.dart' show kProposalConfirmNote;

/// Cross-domain `propose_*` envelope shape. Pass [note] to name the concrete
/// repository call a tool commits to; otherwise the generic
/// [kProposalConfirmNote] is used.
Map<String, Object?> proposalEnvelope({
  required String kind,
  required String summaryZh,
  required Map<String, Object?> payload,
  String note = kProposalConfirmNote,
}) => readyPlan(kind: kind, summaryZh: summaryZh, payload: payload, note: note);

/// Standard `bad_request` tool result. Returned (not thrown) so the agent
/// loop relays the message back to the model.
Map<String, Object?> badRequest(String message) => proposalBadRequest(message);

/// Standard `not_found` tool result carrying the offending [missing] ids.
Map<String, Object?> notFound(String message, List<String> missing) =>
    proposalNotFound(message, missing);
