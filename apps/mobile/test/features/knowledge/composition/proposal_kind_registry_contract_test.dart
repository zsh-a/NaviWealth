import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_proposal_kinds.dart';

void main() {
  test('Knowledge proposal registry matches Knowledge applier kinds', () {
    final registered = kKnowledgeProposalKinds.map((m) => m.kind).toSet();
    expect(registered, kKnowledgeProposalAppliedKinds);
  });
}
