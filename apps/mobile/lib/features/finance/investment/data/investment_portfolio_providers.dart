import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_universe.dart';

import '../domain/allocation/portfolio_allocation_tree.dart';
import '../domain/models/holding_snapshot.dart';
import '../domain/models/investment_portfolio.dart';
import '../domain/models/lot.dart';
import '../domain/models/portfolio_capital_assignment.dart';
import '../domain/strategy/portfolio_strategy.dart';
import '../domain/strategy/portfolio_strategy_template.dart';
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

final portfolioStrategyConfigsProvider =
    StreamProvider.autoDispose<List<PortfolioStrategyConfig>>((ref) async* {
      final ownerUserId = ref.watch(activeUserIdProvider);
      if (ownerUserId == null) {
        yield const [];
        return;
      }
      final repository = await ref.watch(
        investmentPortfolioRepositoryProvider.future,
      );
      yield* repository.watchStrategies(ownerUserId);
    });

final customPortfolioStrategyTemplatesProvider =
    StreamProvider.autoDispose<List<PortfolioStrategyTemplate>>((ref) async* {
      final ownerUserId = ref.watch(activeUserIdProvider);
      if (ownerUserId == null) {
        yield const [];
        return;
      }
      final repository = await ref.watch(
        investmentPortfolioRepositoryProvider.future,
      );
      yield* repository.watchCustomStrategyTemplates(ownerUserId);
    });

final portfolioStrategyTemplatesProvider =
    Provider<AsyncValue<List<PortfolioStrategyTemplate>>>((ref) {
      return ref
          .watch(customPortfolioStrategyTemplatesProvider)
          .whenData(
            (custom) => List.unmodifiable([
              ...kBuiltInPortfolioStrategyTemplates,
              ...custom,
            ]),
          );
    });

final rebalanceUniversesProvider =
    StreamProvider.autoDispose<List<RebalanceUniverse>>((ref) async* {
      final ownerUserId = ref.watch(activeUserIdProvider);
      if (ownerUserId == null) {
        yield const [];
        return;
      }
      final repository = await ref.watch(
        investmentPortfolioRepositoryProvider.future,
      );
      yield* repository.watchUniverses(ownerUserId);
    });

final portfolioAllocationTargetsProvider =
    StreamProvider.autoDispose<List<PortfolioAllocationTarget>>((ref) async* {
      final ownerUserId = ref.watch(activeUserIdProvider);
      if (ownerUserId == null) {
        yield const [];
        return;
      }
      final repository = await ref.watch(
        investmentPortfolioRepositoryProvider.future,
      );
      yield* repository.watchPortfolioTargets(ownerUserId);
    });

final activeRebalanceUniverseProvider =
    Provider<AsyncValue<RebalanceUniverse?>>((ref) {
      return ref
          .watch(rebalanceUniversesProvider)
          .whenData((universes) => universes.firstOrNull);
    });

final activeUniversePortfolioTargetsProvider =
    Provider<AsyncValue<List<PortfolioAllocationTarget>>>((ref) {
      final universe = ref.watch(activeRebalanceUniverseProvider);
      final targets = ref.watch(portfolioAllocationTargetsProvider);
      return universe.when(
        data: (value) => targets.whenData(
          (items) => value == null
              ? const []
              : items
                    .where((target) => target.universeId == value.id)
                    .toList(growable: false),
        ),
        loading: () => const AsyncLoading(),
        error: AsyncError.new,
      );
    });

final portfolioRebalanceGroupsProvider =
    StreamProvider.autoDispose<List<PortfolioRebalanceGroup>>((ref) async* {
      final ownerUserId = ref.watch(activeUserIdProvider);
      if (ownerUserId == null) {
        yield const [];
        return;
      }
      final repository = await ref.watch(
        investmentPortfolioRepositoryProvider.future,
      );
      yield* repository.watchGroups(ownerUserId);
    });

final portfolioCapitalAssignmentsProvider =
    StreamProvider.autoDispose<List<PortfolioCapitalAssignment>>((ref) async* {
      final ownerUserId = ref.watch(activeUserIdProvider);
      if (ownerUserId == null) {
        yield const [];
        return;
      }
      final repository = await ref.watch(
        investmentPortfolioRepositoryProvider.future,
      );
      yield* repository.watchAssignments(ownerUserId);
    });

final portfolioCapitalAssignmentHistoryProvider =
    StreamProvider.autoDispose<List<PortfolioCapitalAssignment>>((ref) async* {
      final ownerUserId = ref.watch(activeUserIdProvider);
      if (ownerUserId == null) {
        yield const [];
        return;
      }
      final repository = await ref.watch(
        investmentPortfolioRepositoryProvider.future,
      );
      yield* repository.watchAssignmentHistory(ownerUserId);
    });

/// One coherent allocation tree for portfolio setup, inspection, and
/// rebalancing. Consumers no longer need to join five persistence streams.
final portfolioAllocationTreeProvider =
    Provider<AsyncValue<PortfolioAllocationTree?>>((ref) {
      final universe = ref.watch(activeRebalanceUniverseProvider);
      final portfolios = ref.watch(investmentPortfoliosProvider);
      final targets = ref.watch(activeUniversePortfolioTargetsProvider);
      final groups = ref.watch(portfolioRebalanceGroupsProvider);
      final strategies = ref.watch(portfolioStrategyConfigsProvider);
      final assignments = ref.watch(portfolioCapitalAssignmentsProvider);

      if (universe.hasError) {
        return AsyncError(universe.error!, universe.stackTrace!);
      }
      if (portfolios.hasError) {
        return AsyncError(portfolios.error!, portfolios.stackTrace!);
      }
      if (targets.hasError) {
        return AsyncError(targets.error!, targets.stackTrace!);
      }
      if (groups.hasError) {
        return AsyncError(groups.error!, groups.stackTrace!);
      }
      if (strategies.hasError) {
        return AsyncError(strategies.error!, strategies.stackTrace!);
      }
      if (assignments.hasError) {
        return AsyncError(assignments.error!, assignments.stackTrace!);
      }
      if (!universe.hasValue ||
          !portfolios.hasValue ||
          !targets.hasValue ||
          !groups.hasValue ||
          !strategies.hasValue ||
          !assignments.hasValue) {
        return const AsyncLoading();
      }
      final root = universe.requireValue;
      if (root == null) return const AsyncData(null);
      return AsyncData(
        PortfolioAllocationTree.compose(
          universe: root,
          portfolios: portfolios.requireValue,
          portfolioTargets: targets.requireValue,
          groups: groups.requireValue,
          strategies: strategies.requireValue,
          assignments: assignments.requireValue,
        ),
      );
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

final selectedPortfolioStrategiesProvider =
    Provider<AsyncValue<List<PortfolioStrategyConfig>>>((ref) {
      final selectedId = ref.watch(
        effectiveSelectedInvestmentPortfolioIdProvider,
      );
      return ref
          .watch(portfolioStrategyConfigsProvider)
          .whenData(
            (strategies) => selectedId == null
                ? const []
                : strategies
                      .where((strategy) => strategy.portfolioId == selectedId)
                      .toList(growable: false),
          );
    });

final selectedPortfolioRebalanceGroupsProvider =
    Provider<AsyncValue<List<PortfolioRebalanceGroup>>>((ref) {
      final selectedId = ref.watch(
        effectiveSelectedInvestmentPortfolioIdProvider,
      );
      return ref
          .watch(portfolioRebalanceGroupsProvider)
          .whenData(
            (groups) => selectedId == null
                ? const []
                : groups
                      .where((group) => group.portfolioId == selectedId)
                      .toList(growable: false),
          );
    });

class ScopedPortfolioHoldings {
  const ScopedPortfolioHoldings({
    required this.snapshots,
    required this.lots,
    required this.snapshotsByGroup,
    required this.cashAssignments,
  });

  final Map<String, HoldingSnapshot> snapshots;
  final List<Lot> lots;
  final Map<String, Map<String, HoldingSnapshot>> snapshotsByGroup;
  final List<PortfolioCapitalAssignment> cashAssignments;
}

/// Holdings narrowed to authored capital assignments.
///
/// A selected portfolio may own whole or partial lots. Group snapshots retain
/// the exclusive capital partition for hierarchical rebalancing. Cash remains
/// an explicit assignment and is resolved against account balances by the
/// rebalance snapshot provider.
final scopedPortfolioHoldingsProvider =
    FutureProvider.autoDispose<ScopedPortfolioHoldings>((ref) async {
      final snapshotsFuture = ref.watch(holdingsSnapshotProvider.future);
      final holdingServiceFuture = ref.watch(holdingServiceProvider.future);
      final assignmentsFuture = ref.watch(
        portfolioCapitalAssignmentsProvider.future,
      );
      final selectedId = ref.watch(
        effectiveSelectedInvestmentPortfolioIdProvider,
      );
      final snapshots = await snapshotsFuture;
      final holdingService = await holdingServiceFuture;
      final assignments = await assignmentsFuture;
      final lots = await holdingService.lotsAt(DateTime.now().toUtc());
      return scopePortfolioHoldings(
        snapshots: snapshots,
        lots: lots,
        assignments: assignments,
        selectedPortfolioId: selectedId,
      );
    });

final allPortfolioScopedHoldingsProvider =
    FutureProvider.autoDispose<Map<String, ScopedPortfolioHoldings>>((
      ref,
    ) async {
      final snapshots = await ref.watch(holdingsSnapshotProvider.future);
      final holdingService = await ref.watch(holdingServiceProvider.future);
      final assignments = await ref.watch(
        portfolioCapitalAssignmentsProvider.future,
      );
      final portfolios = await ref.watch(investmentPortfoliosProvider.future);
      final lots = await holdingService.lotsAt(DateTime.now().toUtc());
      return Map.unmodifiable({
        for (final portfolio in portfolios)
          portfolio.id: scopePortfolioHoldings(
            snapshots: snapshots,
            lots: lots,
            assignments: assignments,
            selectedPortfolioId: portfolio.id,
          ),
      });
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
  required List<PortfolioCapitalAssignment> assignments,
  required String? selectedPortfolioId,
}) {
  if (selectedPortfolioId == null) {
    return ScopedPortfolioHoldings(
      snapshots: Map.unmodifiable(snapshots),
      lots: List.unmodifiable(lots),
      snapshotsByGroup: const {},
      cashAssignments: const [],
    );
  }

  final lotById = {for (final lot in lots) lot.id: lot};
  _validateAssignments(lotById, assignments);
  final lotAssignments = assignments
      .where(
        (assignment) => assignment.sourceKind == PortfolioCapitalSourceKind.lot,
      )
      .toList(growable: false);
  final selectedSlices = <Lot>[];
  final slicesByGroup = <String, List<Lot>>{};

  if (selectedPortfolioId == kUnassignedInvestmentPortfolioId) {
    final assignedByLot = <String, Decimal>{};
    for (final assignment in lotAssignments) {
      final lot = lotById[assignment.sourceId];
      if (lot == null || lot.isClosed) continue;
      final quantity = assignment.quantity ?? lot.remainingQuantity;
      assignedByLot.update(
        lot.id,
        (value) => value + quantity,
        ifAbsent: () => quantity,
      );
    }
    for (final lot in lots.where((lot) => !lot.isClosed)) {
      final quantity =
          lot.remainingQuantity - (assignedByLot[lot.id] ?? Decimal.zero);
      if (quantity > Decimal.zero) {
        selectedSlices.add(_sliceLot(lot, quantity));
      }
    }
  } else {
    final selectedAssignments = lotAssignments.where(
      (assignment) => assignment.portfolioId == selectedPortfolioId,
    );
    final quantityByLot = <String, Decimal>{};
    for (final assignment in selectedAssignments) {
      final lot = lotById[assignment.sourceId];
      if (lot == null || lot.isClosed) continue;
      final quantity = assignment.quantity ?? lot.remainingQuantity;
      final slice = _sliceLot(lot, quantity);
      slicesByGroup
          .putIfAbsent(assignment.rebalanceGroupId, () => [])
          .add(slice);
      quantityByLot.update(
        lot.id,
        (value) => value + quantity,
        ifAbsent: () => quantity,
      );
    }
    for (final entry in quantityByLot.entries) {
      selectedSlices.add(_sliceLot(lotById[entry.key]!, entry.value));
    }
  }

  final scoped = _scopeSnapshots(
    snapshots: snapshots,
    allLots: lots,
    slices: selectedSlices,
  );
  final snapshotsByGroup = <String, Map<String, HoldingSnapshot>>{
    for (final entry in slicesByGroup.entries)
      entry.key: _scopeSnapshots(
        snapshots: snapshots,
        allLots: lots,
        slices: entry.value,
      ),
  };
  final cashAssignments = assignments
      .where(
        (assignment) =>
            assignment.sourceKind == PortfolioCapitalSourceKind.cashAccount &&
            assignment.portfolioId == selectedPortfolioId,
      )
      .toList(growable: false);
  return ScopedPortfolioHoldings(
    snapshots: Map.unmodifiable(scoped),
    lots: List.unmodifiable(selectedSlices),
    snapshotsByGroup: Map.unmodifiable(snapshotsByGroup),
    cashAssignments: List.unmodifiable(cashAssignments),
  );
}

void _validateAssignments(
  Map<String, Lot> lotById,
  List<PortfolioCapitalAssignment> assignments,
) {
  final assignedByLot = <String, Decimal>{};
  final wholeLotOwners = <String>{};
  for (final assignment in assignments) {
    assignment.validate();
    if (assignment.sourceKind != PortfolioCapitalSourceKind.lot) continue;
    final lot = lotById[assignment.sourceId];
    if (lot == null || lot.isClosed) continue;
    if (assignment.quantity == null) {
      if (!wholeLotOwners.add(lot.id) || assignedByLot.containsKey(lot.id)) {
        throw StateError('Lot ${lot.id} has more than one capital owner.');
      }
      assignedByLot[lot.id] = lot.remainingQuantity;
      continue;
    }
    if (wholeLotOwners.contains(lot.id)) {
      throw StateError('Lot ${lot.id} has more than one capital owner.');
    }
    final assigned =
        (assignedByLot[lot.id] ?? Decimal.zero) + assignment.quantity!;
    if (assigned > lot.remainingQuantity) {
      throw StateError('Lot ${lot.id} is assigned beyond its open quantity.');
    }
    assignedByLot[lot.id] = assigned;
  }
}

Lot _sliceLot(Lot lot, Decimal quantity) =>
    lot.copyWith(originalQuantity: quantity, remainingQuantity: quantity);

Map<String, HoldingSnapshot> _scopeSnapshots({
  required Map<String, HoldingSnapshot> snapshots,
  required List<Lot> allLots,
  required List<Lot> slices,
}) {
  final allQuantity = <String, Decimal>{};
  final selectedQuantity = <String, Decimal>{};
  final allCost = <String, Decimal>{};
  final selectedCost = <String, Decimal>{};
  for (final lot in allLots.where((lot) => !lot.isClosed)) {
    allQuantity.update(
      lot.assetId,
      (value) => value + lot.remainingQuantity,
      ifAbsent: () => lot.remainingQuantity,
    );
    final cost = lot.remainingQuantity * lot.costPerUnit;
    allCost.update(lot.assetId, (value) => value + cost, ifAbsent: () => cost);
  }
  for (final lot in slices.where((lot) => !lot.isClosed)) {
    selectedQuantity.update(
      lot.assetId,
      (value) => value + lot.remainingQuantity,
      ifAbsent: () => lot.remainingQuantity,
    );
    final cost = lot.remainingQuantity * lot.costPerUnit;
    selectedCost.update(
      lot.assetId,
      (value) => value + cost,
      ifAbsent: () => cost,
    );
  }

  final scoped = <String, HoldingSnapshot>{};
  var totalMarketValue = Decimal.zero;
  for (final entry in snapshots.entries) {
    final source = entry.value;
    final quantity = selectedQuantity[entry.key] ?? Decimal.zero;
    final totalQuantity = allQuantity[entry.key] ?? Decimal.zero;
    if (quantity <= Decimal.zero || totalQuantity <= Decimal.zero) continue;
    final ratio = (quantity / totalQuantity).toDecimal(
      scaleOnInfinitePrecision: 12,
    );
    final totalCost = allCost[entry.key] ?? Decimal.zero;
    final costRatio = totalCost <= Decimal.zero
        ? ratio
        : ((selectedCost[entry.key] ?? Decimal.zero) / totalCost).toDecimal(
            scaleOnInfinitePrecision: 12,
          );
    final marketValueInAssetCurrency =
        source.marketValueInAssetCurrency * ratio;
    final marketValueInBase = source.marketValueInBase * ratio;
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

  if (totalMarketValue > Decimal.zero) {
    for (final entry in scoped.entries.toList(growable: false)) {
      scoped[entry.key] = entry.value.copyWith(
        weight: (entry.value.marketValueInBase / totalMarketValue).toDecimal(
          scaleOnInfinitePrecision: 8,
        ),
      );
    }
  }
  return scoped;
}
