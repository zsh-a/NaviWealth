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
      children: [child],
      createdAt: DateTime.utc(2026, 6, 19, 12),
      expiresAt: DateTime.utc(2026, 6, 19, 12, 1),
    );

    expect(entry.kind, kBatchProposalUndoKind);
    expect(entry.showGlobalBanner, isFalse);
    expect(entry.payload['proposal_id'], 'batch-1');
    expect(entry.payload['summary_zh'], '批量记录 1 项支出');

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
