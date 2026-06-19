/// Shared wire-envelope helpers for cross-domain `propose_*` device tools.
///
/// The UI parses this shape in [ProposalPlan.tryParse]. Domain tools own
/// their payload semantics; this file owns only the stable outer envelope
/// and standard tool error bodies.
library;

import 'package:uuid/uuid.dart';

const _kUuid = Uuid();

/// Default `note` carried on proposal envelopes: the UI must surface
/// `summary_zh` and only commit after explicit user confirmation.
const String kProposalConfirmNote =
    'Surface summary_zh for explicit user confirmation before applying via a repository.';

/// Pre-allocated id for new proposal payload entities.
String proposalNewId() => _kUuid.v4();

/// `status = ready` proposal envelope.
Map<String, Object?> readyPlan({
  required String kind,
  required String summaryZh,
  required Map<String, Object?> payload,
  String envelopeKind = 'local_proposal',
  List<String> warnings = const [],
  List<String> missing = const [],
  String note = kProposalConfirmNote,
}) => <String, Object?>{
  'proposal_id': _kUuid.v4(),
  'kind': kind,
  'status': 'ready',
  'envelope_kind': envelopeKind,
  'summary_zh': summaryZh,
  'payload': payload,
  'warnings': warnings,
  'missing': missing,
  'candidates': null,
  'note': note,
};

/// `status = needs_clarification` proposal envelope.
Map<String, Object?> needsClarification({
  required String kind,
  required String field,
  required String reason,
  required List<Map<String, Object?>> candidates,
  String note =
      'Ask the user one concrete clarification question for this field; do not choose on their behalf.',
}) => <String, Object?>{
  'proposal_id': _kUuid.v4(),
  'kind': kind,
  'status': 'needs_clarification',
  'ambiguous_field': field,
  'reason': reason,
  'candidates': candidates,
  'note': note,
};

/// Standard `bad_request` tool result. Returned, not thrown, so the agent
/// loop can relay the message back to the model.
Map<String, Object?> proposalBadRequest(String message) => <String, Object?>{
  'error': message,
  'code': 'bad_request',
};

/// Standard `not_found` tool result carrying the offending ids.
Map<String, Object?> proposalNotFound(String message, List<String> missing) =>
    <String, Object?>{
      'error': message,
      'code': 'not_found',
      'missing': missing,
    };
