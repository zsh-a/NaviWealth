import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

enum PortfolioCapitalSourceKind { lot, cashAccount }

PortfolioCapitalSourceKind portfolioCapitalSourceKindFromWire(String wire) {
  return PortfolioCapitalSourceKind.values.firstWhere(
    (value) => value.name == wire,
    orElse: () =>
        throw FormatException('Unknown portfolio capital source kind: $wire.'),
  );
}

/// Assigns an economic unit to exactly one capital-owning rebalance group.
///
/// Lot assignments may own the entire remaining lot ([quantity] is null) or a
/// fixed quantity. Cash assignments reserve [amount] from one account.
/// Strategy overlays reference these assignments; they never create a second
/// owner for the same capital.
class PortfolioCapitalAssignment {
  const PortfolioCapitalAssignment({
    required this.id,
    required this.portfolioId,
    required this.rebalanceGroupId,
    required this.sourceKind,
    required this.sourceId,
    required this.quantity,
    required this.amount,
    required this.currency,
    required this.assignedAt,
    this.unassignedAt,
    required this.sync,
  });

  final String id;
  final String portfolioId;
  final String rebalanceGroupId;
  final PortfolioCapitalSourceKind sourceKind;
  final String sourceId;
  final Decimal? quantity;
  final Decimal? amount;
  final String? currency;
  final DateTime assignedAt;
  final DateTime? unassignedAt;
  final SyncMeta sync;

  bool get isWholeLot =>
      sourceKind == PortfolioCapitalSourceKind.lot && quantity == null;

  bool get isActive => unassignedAt == null;

  bool isActiveAt(DateTime instant) {
    final at = instant.toUtc();
    return !assignedAt.toUtc().isAfter(at) &&
        (unassignedAt == null || unassignedAt!.toUtc().isAfter(at));
  }

  void validate() {
    if (portfolioId.trim().isEmpty ||
        rebalanceGroupId.trim().isEmpty ||
        sourceId.trim().isEmpty) {
      throw const FormatException(
        'Capital assignment identifiers must not be empty.',
      );
    }
    if (unassignedAt != null &&
        unassignedAt!.toUtc().isBefore(assignedAt.toUtc())) {
      throw const FormatException(
        'Capital assignment cannot end before it starts.',
      );
    }
    switch (sourceKind) {
      case PortfolioCapitalSourceKind.lot:
        if (amount != null || currency != null) {
          throw const FormatException(
            'Lot assignments cannot carry cash amount or currency.',
          );
        }
        if (quantity != null && quantity! <= Decimal.zero) {
          throw const FormatException(
            'Assigned lot quantity must be positive.',
          );
        }
      case PortfolioCapitalSourceKind.cashAccount:
        if (quantity != null ||
            amount == null ||
            amount! <= Decimal.zero ||
            currency?.trim().isEmpty != false) {
          throw const FormatException(
            'Cash assignments require a positive amount and currency.',
          );
        }
    }
  }
}
