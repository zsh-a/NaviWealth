import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';

import '../domain/allocation/portfolio_allocation_tree.dart';

/// Render-ready counts for the portfolio studio header.
final class PortfolioStudioSummary {
  const PortfolioStudioSummary({
    required this.sleeveCount,
    required this.includedAssetCount,
    required this.secondaryRuleCount,
  });

  factory PortfolioStudioSummary.fromTree({
    required PortfolioAllocationTree tree,
    required List<AllocationNode> sleeves,
  }) {
    var includedAssetCount = 0;
    var secondaryRuleCount = 0;
    for (final sleeve in sleeves) {
      includedAssetCount += tree.inclusionsFor(sleeve.id).length;
      secondaryRuleCount += tree
          .attachmentsFor(sleeve.id)
          .where((attachment) => !attachment.isPrimary)
          .length;
    }
    return PortfolioStudioSummary(
      sleeveCount: sleeves.length,
      includedAssetCount: includedAssetCount,
      secondaryRuleCount: secondaryRuleCount,
    );
  }

  final int sleeveCount;
  final int includedAssetCount;
  final int secondaryRuleCount;
}

/// Resolved labels and defaults for a transfer task shown in the studio.
final class PortfolioTransferTaskProjection {
  const PortfolioTransferTaskProjection({
    required this.fromName,
    required this.toName,
    required this.amount,
    required this.preferredGroupId,
  });

  factory PortfolioTransferTaskProjection.fromIntent({
    required CapitalTransferIntent intent,
    required PortfolioAllocationTree tree,
    required Map<String, String> portfolioNames,
  }) {
    final targetPortfolioNode = tree.nodeForReference(
      AllocationNodeType.portfolio,
      intent.toPortfolioId,
    );
    return PortfolioTransferTaskProjection(
      fromName: _resolveEndpointName(
        portfolioId: intent.fromPortfolioId,
        groupId: intent.fromGroupId,
        tree: tree,
        portfolioNames: portfolioNames,
      ),
      toName: _resolveEndpointName(
        portfolioId: intent.toPortfolioId,
        groupId: intent.toGroupId,
        tree: tree,
        portfolioNames: portfolioNames,
      ),
      amount: Decimal.tryParse(intent.amount),
      preferredGroupId:
          intent.toGroupId ??
          (targetPortfolioNode == null
              ? null
              : tree
                    .childrenOf(targetPortfolioNode.id)
                    .firstOrNull
                    ?.referenceId),
    );
  }

  final String fromName;
  final String toName;
  final Decimal? amount;
  final String? preferredGroupId;
}

String _resolveEndpointName({
  required String portfolioId,
  required String? groupId,
  required PortfolioAllocationTree tree,
  required Map<String, String> portfolioNames,
}) {
  if (groupId == null) return portfolioNames[portfolioId] ?? portfolioId;
  return tree.nodeForReference(AllocationNodeType.sleeve, groupId)?.name ??
      groupId;
}
