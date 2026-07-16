import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_kind_registry.dart';
import 'package:naviwealth/features/finance/composition/finance_proposal_kinds.dart';

void main() {
  test('Finance proposal registry matches Finance applier kinds', () {
    final registered = kFinanceProposalKinds.map((m) => m.kind).toSet();
    expect(registered, kFinanceProposalAppliedKinds);
  });

  test('Finance proposal registry remains presentation-only', () {
    expect(
      kFinanceProposalKinds.metaFor('expense')!.toolName,
      'propose_expense',
    );
    expect(kFinanceProposalKinds.metaFor('income')!.toolName, 'propose_income');
    expect(kFinanceProposalKinds.metaFor('trade')!.toolName, 'propose_trade');
    expect(
      kFinanceProposalKinds.metaFor('options_journal_entry')!.toolName,
      'propose_options_journal_entry',
    );
  });
}
