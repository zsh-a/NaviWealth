import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/batch_proposal_undo.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';

void main() {
  test('buildBatchProposalUndoEntry stores child reversal states', () {
    final child = ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: 'je-1',
      appliedTable: 'journal_entries',
      appliedAt: DateTime.utc(2026, 6, 19, 12),
    );

    final entry = buildBatchProposalUndoEntry(
      token: 'batch-token',
      proposalId: 'batch-1',
      summaryZh: '批量记录 1 项支出',
      chatSessionId: 'session-1',
      chatMessageId: 'message-1',
      chatToolInvocationId: 'tool-1',
      children: [child],
      createdAt: DateTime.utc(2026, 6, 19, 12),
      expiresAt: DateTime.utc(2026, 6, 19, 12, 1),
    );

    expect(entry.kind, kBatchProposalUndoKind);
    expect(entry.showGlobalBanner, isTrue);
    expect(entry.payload['proposal_id'], 'batch-1');
    expect(entry.payload['summary_zh'], '批量记录 1 项支出');
    expect(entry.payload['chat_session_id'], 'session-1');
    expect(entry.payload['chat_message_id'], 'message-1');
    expect(entry.payload['chat_tool_invocation_id'], 'tool-1');

    final children = batchProposalUndoChildren(entry.payload);
    expect(children, hasLength(1));
    expect(children.single.appliedEntityId, child.appliedEntityId);
    expect(children.single.appliedTable, child.appliedTable);
  });

  test('batchProposalUndoChildren rejects malformed payloads', () {
    expect(
      () => batchProposalUndoChildren(const <String, Object?>{}),
      throwsA(isA<FormatException>()),
    );
  });
}
