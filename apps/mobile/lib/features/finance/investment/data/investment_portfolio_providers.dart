import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';

import '../domain/models/holding_snapshot.dart';
import '../domain/models/investment_portfolio.dart';
import '../domain/models/lot.dart';
import 'investment_portfolio_repository.dart';
import 'providers.dart';

const String kUnassignedInvestmentPortfolioId = '__unassigned__';

final investmentPortfolioRepositoryProvider =
    FutureProvider<InvestmentPortfolioRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final outbox = await ref.watch(outboxStoreProvider.future);
      final stamper = await ref.watch(mutationStamperProvider.future);
      return InvestmentPortfolioRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
    });

final investmentPortfoliosProvider =
    StreamProvider.autoDispose<List<InvestmentPortfolio>>((ref) async* {
      final ownerUserId = ref.watch(activeUserIdProvider);
      if (ownerUserId == null) {
        yield const [];
        return;
      }
      final repository = await ref.watch(
        investmentPortfolioRepositoryProvider.future,
      );
      yield* repository.watchActive(ownerUserId);
    });

final portfolioLotMembershipsProvider =
    StreamProvider.autoDispose<List<PortfolioLotMembership>>((ref) async* {
      final ownerUserId = ref.watch(activeUserIdProvider);
      if (ownerUserId == null) {
        yield const [];
        return;
      }
      final repository = await ref.watch(
        investmentPortfolioRepositoryProvider.future,
      );
      yield* repository.watchMemberships(ownerUserId);
    });

/// Null selects the virtual all-holdings portfolio.
final selectedInvestmentPortfolioIdProvider = StateProvider<String?>(
  (ref) => null,
);

final effectiveSelectedInvestmentPortfolioIdProvider = Provider<String?>((ref) {
  final selectedId = ref.watch(selectedInvestmentPortfolioIdProvider);
  if (selectedId == null || selectedId == kUnassignedInvestmentPortfolioId) {
    return selectedId;
  }
  final portfolios = ref.watch(investmentPortfoliosProvider);
  if (!portfolios.hasValue) return selectedId;
  return portfolios.requireValue.any((portfolio) => portfolio.id == selectedId)
      ? selectedId
      : null;
});

final selectedInvestmentPortfolioProvider =
    Provider<AsyncValue<InvestmentPortfolio?>>((ref) {
      final selectedId = ref.watch(
        effectiveSelectedInvestmentPortfolioIdProvider,
      );
      return ref.watch(investmentPortfoliosProvider).whenData((portfolios) {
        if (selectedId == null) return null;
        for (final portfolio in portfolios) {
          if (portfolio.id == selectedId) return portfolio;
        }
        return null;
      });
    });

class ScopedPortfolioHoldings {
  const ScopedPortfolioHoldings({required this.snapshots, required this.lots});

  final Map<String, HoldingSnapshot> snapshots;
  final List<Lot> lots;
}

/// Holdings narrowed to the selected logical portfolio. Null keeps the
/// virtual all-holdings view; [kUnassignedInvestmentPortfolioId] selects lots
/// without a membership row.
final scopedPortfolioHoldingsProvider =
    FutureProvider.autoDispose<ScopedPortfolioHoldings>((ref) async {
      final snapshotsFuture = ref.watch(holdingsSnapshotProvider.future);
      final holdingServiceFuture = ref.watch(holdingServiceProvider.future);
      final membershipsFuture = ref.watch(
        portfolioLotMembershipsProvider.future,
      );
      final selectedId = ref.watch(
        effectiveSelectedInvestmentPortfolioIdProvider,
      );
      final snapshots = await snapshotsFuture;
      final holdingService = await holdingServiceFuture;
      final memberships = await membershipsFuture;
      final lots = await holdingService.lotsAt(DateTime.now().toUtc());
      return scopePortfolioHoldings(
        snapshots: snapshots,
        lots: lots,
        memberships: memberships,
        selectedPortfolioId: selectedId,
      );
    });

final allInvestmentLotsProvider = FutureProvider.autoDispose<List<Lot>>((
  ref,
) async {
  final service = await ref.watch(holdingServiceProvider.future);
  return service.lotsAt(DateTime.now().toUtc());
});

ScopedPortfolioHoldings scopePortfolioHoldings({
  required Map<String, HoldingSnapshot> snapshots,
  required List<Lot> lots,
  required List<PortfolioLotMembership> memberships,
  required String? selectedPortfolioId,
}) {
  if (selectedPortfolioId == null) {
    return ScopedPortfolioHoldings(
      snapshots: Map.unmodifiable(snapshots),
      lots: List.unmodifiable(lots),
    );
  }

  final portfolioByLot = <String, String>{
    for (final membership in memberships)
      membership.lotId: membership.portfolioId,
  };
  final selectedLots = lots
      .where((lot) {
        final assignedPortfolio = portfolioByLot[lot.id];
        if (selectedPortfolioId == kUnassignedInvestmentPortfolioId) {
          return assignedPortfolio == null;
        }
        return assignedPortfolio == selectedPortfolioId;
      })
      .toList(growable: false);

  final allQuantity = <String, Decimal>{};
  final allCost = <String, Decimal>{};
  final selectedQuantity = <String, Decimal>{};
  final selectedCost = <String, Decimal>{};
  for (final lot in lots.where((lot) => !lot.isClosed)) {
    allQuantity.update(
      lot.assetId,
      (value) => value + lot.remainingQuantity,
      ifAbsent: () => lot.remainingQuantity,
    );
    allCost.update(
      lot.assetId,
      (value) => value + lot.remainingCost,
      ifAbsent: () => lot.remainingCost,
    );
  }
  for (final lot in selectedLots.where((lot) => !lot.isClosed)) {
    selectedQuantity.update(
      lot.assetId,
      (value) => value + lot.remainingQuantity,
      ifAbsent: () => lot.remainingQuantity,
    );
    selectedCost.update(
      lot.assetId,
      (value) => value + lot.remainingCost,
      ifAbsent: () => lot.remainingCost,
    );
  }

  final scoped = <String, HoldingSnapshot>{};
  var totalMarketValue = Decimal.zero;
  for (final entry in snapshots.entries) {
    final source = entry.value;
    final quantity = selectedQuantity[entry.key] ?? Decimal.zero;
    final totalQuantity = allQuantity[entry.key] ?? Decimal.zero;
    if (quantity.sign <= 0 || totalQuantity.sign <= 0) continue;
    final quantityRatio = (quantity / totalQuantity).toDecimal(
      scaleOnInfinitePrecision: 12,
    );
    final cost = selectedCost[entry.key] ?? Decimal.zero;
    final totalCost = allCost[entry.key] ?? Decimal.zero;
    final costRatio = totalCost.sign <= 0
        ? quantityRatio
        : (cost / totalCost).toDecimal(scaleOnInfinitePrecision: 12);
    final marketValueInAssetCurrency =
        source.marketValueInAssetCurrency * quantityRatio;
    final marketValueInBase = source.marketValueInBase * quantityRatio;
    final costBasisInAssetCurrency =
        source.costBasisInAssetCurrency * costRatio;
    final costBasisInBase = source.costBasisInBase * costRatio;
    totalMarketValue += marketValueInBase;
    scoped[entry.key] = HoldingSnapshot(
      assetId: source.assetId,
      quantity: quantity,
      costBasisInAssetCurrency: costBasisInAssetCurrency,
      marketValueInAssetCurrency: marketValueInAssetCurrency,
      assetCurrency: source.assetCurrency,
      costBasisInBase: costBasisInBase,
      marketValueInBase: marketValueInBase,
      unrealizedPnlInBase: marketValueInBase - costBasisInBase,
      weight: Decimal.zero,
      baseCurrency: source.baseCurrency,
      asOf: source.asOf,
      unitPriceInAssetCurrency: source.unitPriceInAssetCurrency,
      priceConfidence: source.priceConfidence,
      priceSource: source.priceSource,
      priceAsOf: source.priceAsOf,
    );
  }

  if (totalMarketValue.sign > 0) {
    for (final entry in scoped.entries.toList(growable: false)) {
      scoped[entry.key] = entry.value.copyWith(
        weight: (entry.value.marketValueInBase / totalMarketValue).toDecimal(
          scaleOnInfinitePrecision: 8,
        ),
      );
    }
  }
  return ScopedPortfolioHoldings(
    snapshots: Map.unmodifiable(scoped),
    lots: List.unmodifiable(selectedLots),
  );
}
