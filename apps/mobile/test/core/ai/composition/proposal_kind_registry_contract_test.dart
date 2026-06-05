import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/composition/finance_proposal_applier.dart';
import 'package:naviwealth/features/finance/composition/finance_proposal_kinds.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_proposal_applier.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_proposal_kinds.dart';

void main() {
  test('Finance proposal registry matches Finance applier kinds', () {
    final registered = kFinanceProposalKinds.map((m) => m.kind).toSet();
    expect(registered, kFinanceProposalAppliedKinds);
  });

  test('Knowledge proposal registry matches Knowledge applier kinds', () {
    final registered = kKnowledgeProposalKinds.map((m) => m.kind).toSet();
    expect(registered, kKnowledgeProposalAppliedKinds);
  });
}
