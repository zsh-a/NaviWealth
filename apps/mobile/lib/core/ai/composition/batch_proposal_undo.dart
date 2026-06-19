/// Persisted undo payload helpers for batch proposal applies.
///
/// A batch proposal applies several child [ReadyProposalPlan]s after one user
/// confirmation. The actual child reversal states can be larger than a chat
/// card should own, so new batch applies store them as a `batch_undo` entry in
/// `ai_undo_stack` and keep only the token on [ProposalApplyState].
library;

import '../write/drift_undo_stack.dart';
import 'proposal_apply_state.dart';

const kBatchProposalAppliedTable = '__batch__';
const kBatchProposalUndoKind = 'batch_undo';

PersistedUndoEntry buildBatchProposalUndoEntry({
  required String token,
  required String proposalId,
  required String summaryZh,
  required String chatSessionId,
  required String chatMessageId,
  required String chatToolInvocationId,
  required List<ProposalApplyState> children,
  required DateTime createdAt,
  required DateTime expiresAt,
}) {
  return PersistedUndoEntry(
    token: token,
    kind: kBatchProposalUndoKind,
    payload: <String, Object?>{
      'proposal_id': proposalId,
      'summary_zh': summaryZh,
      'chat_session_id': chatSessionId,
      'chat_message_id': chatMessageId,
      'chat_tool_invocation_id': chatToolInvocationId,
      'children': [for (final child in children) child.toJson()],
      'show_global_banner': true,
    },
    createdAt: createdAt,
    expiresAt: expiresAt,
  );
}

List<ProposalApplyState> batchProposalUndoChildren(
  Map<String, Object?> payload,
) {
  final rawChildren = payload['children'];
  if (rawChildren is! List) {
    throw const FormatException('batch undo data missing children');
  }
  return rawChildren
      .whereType<Map<Object?, Object?>>()
      .map(
        (m) => ProposalApplyState.fromJson(
          m.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .toList(growable: false);
}
