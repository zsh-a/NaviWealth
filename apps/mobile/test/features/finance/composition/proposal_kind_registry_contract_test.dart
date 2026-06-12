import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_kind_registry.dart';
import 'package:naviwealth/core/ai/write/interaction_mode.dart';
import 'package:naviwealth/features/finance/composition/finance_proposal_kinds.dart';

void main() {
  test('Finance proposal registry matches Finance applier kinds', () {
    final registered = kFinanceProposalKinds.map((m) => m.kind).toSet();
    expect(registered, kFinanceProposalAppliedKinds);
  });

  test('Finance proposal interaction modes are declared by specs', () {
    expect(
      kFinanceProposalKinds.metaFor('expense')!.interactionMode,
      InteractionMode.oneTap,
    );
    expect(
      kFinanceProposalKinds.metaFor('trade')!.interactionMode,
      InteractionMode.confirmDiff,
    );
    expect(
      kFinanceProposalKinds.metaFor('options_journal_entry')!.interactionMode,
      InteractionMode.confirmDiff,
    );
  });
}
