import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/rebalance/domain/capital_allocation_engine.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';

void main() {
  const engine = CapitalAllocationEngine();

  test('matches eligible surplus and deficit at any capital-tree level', () {
    final plan = engine.compute(
      baseCurrency: 'USD',
      nodes: [
        _node(
          id: 'growth',
          actual: '800',
          targetWeightBps: 5000,
          policy: GroupTransferPolicy.bidirectional,
        ),
        _node(
          id: 'income',
          actual: '200',
          targetWeightBps: 5000,
          policy: GroupTransferPolicy.inflowsOnly,
        ),
      ],
    );

    expect(plan.totalAssets.amount, Decimal.parse('1000'));
    expect(plan.transfers, hasLength(1));
    expect(plan.transfers.single.fromNodeId, 'growth');
    expect(plan.transfers.single.toNodeId, 'income');
    expect(plan.transfers.single.amount.amount, Decimal.parse('300.00000000'));
    expect(
      plan.decisions['growth']!.action,
      CapitalAllocationAction.transferOut,
    );
    expect(
      plan.decisions['income']!.action,
      CapitalAllocationAction.transferIn,
    );
  });

  test('isolated allocation blocks both inflows and outflows', () {
    final plan = engine.compute(
      baseCurrency: 'USD',
      nodes: [
        _node(
          id: 'core',
          actual: '800',
          targetWeightBps: 5000,
          policy: GroupTransferPolicy.bidirectional,
        ),
        _node(
          id: 'isolated',
          actual: '200',
          targetWeightBps: 5000,
          policy: GroupTransferPolicy.isolated,
        ),
      ],
    );

    expect(plan.transfers, isEmpty);
    expect(
      plan.decisions['isolated']!.action,
      CapitalAllocationAction.policyBlocked,
    );
    expect(plan.hasBlockedDecisions, isTrue);
    expect(plan.requiresAction, isTrue);
  });

  test('requires an exact 100% target total', () {
    expect(
      () => engine.compute(
        baseCurrency: 'USD',
        nodes: [
          _node(
            id: 'invalid',
            actual: '100',
            targetWeightBps: 9000,
            policy: GroupTransferPolicy.bidirectional,
          ),
        ],
      ),
      throwsFormatException,
    );
  });
}

CapitalAllocationNode _node({
  required String id,
  required String actual,
  required int targetWeightBps,
  required GroupTransferPolicy policy,
}) {
  return CapitalAllocationNode(
    id: id,
    name: id,
    targetWeightBps: targetWeightBps,
    driftBandBps: 0,
    transferPolicy: policy,
    actualAmount: Decimal.parse(actual),
  );
}
