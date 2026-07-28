import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/data/preferences/risk_appetite_preferences.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_repository.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_capital_assignment.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../design_system/preferences/theme_preferences.dart';
import '../application/rebalance_execution_coordinator.dart';
import '../application/rebalance_execution_workspace_gateway.dart';
import '../application/rebalance_trade_validation.dart';
import '../domain/allocation_schemes.dart';
import '../domain/hierarchical_rebalance_engine.dart';
import '../domain/portfolio_rebalance_group.dart';
import '../domain/rebalance_engine.dart';
import '../domain/rebalance_execution.dart';
import '../domain/rebalance_models.dart';
import '../domain/rebalance_universe.dart';
import '../domain/universe_rebalance_engine.dart';
import 'rebalance_execution_store.dart';

const _kWarningThresholdKey = 'naviwealth.rebalance.warning_threshold';
const _kCriticalThresholdKey = 'naviwealth.rebalance.critical_threshold';

final rebalanceExecutionStoreProvider = FutureProvider<RebalanceExecutionStore>(
  (ref) async {
    final db = await ref.watch(appDatabaseProvider.future);
    return RebalanceExecutionStore(db);
  },
);

final rebalanceTradeValidationProvider =
    FutureProvider<RebalanceTradeValidation>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      return RebalanceTradeValidation(db);
    });

final rebalanceExecutionCoordinatorProvider =
    FutureProvider<RebalanceExecutionCoordinator>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final store = await ref.watch(rebalanceExecutionStoreProvider.future);
      final validation = await ref.watch(
        rebalanceTradeValidationProvider.future,
      );
      final tradeSubmission = await ref.watch(
        tradeEntrySubmissionServiceProvider.future,
      );
      return RebalanceExecutionCoordinator(
        db: db,
        store: store,
        validation: validation,
        tradeSubmission: tradeSubmission,
        currentUserId: ref.watch(currentUserIdProvider),
      );
    });

final rebalanceExecutionWorkspaceGatewayProvider =
    FutureProvider<RebalanceExecutionWorkspaceGateway>((ref) async {
      ref.watch(activeUserIdProvider);
      final db = await ref.watch(appDatabaseProvider.future);
      final store = await ref.watch(rebalanceExecutionStoreProvider.future);
      final validation = await ref.watch(
        rebalanceTradeValidationProvider.future,
      );
      final coordinator = await ref.watch(
        rebalanceExecutionCoordinatorProvider.future,
      );
      return DefaultRebalanceExecutionWorkspaceGateway(
        db: db,
        store: store,
        validation: validation,
        coordinator: coordinator,
        currentUserId: ref.watch(currentUserIdProvider),
      );
    });

final activeRebalanceExecutionProvider =
    FutureProvider.autoDispose<RebalanceExecutionSession?>((ref) async {
      ref.watch(activeUserIdProvider);
      final gateway = await ref.watch(
        rebalanceExecutionWorkspaceGatewayProvider.future,
      );
      return gateway.active();
    });

final rebalanceExecutionSessionProvider = FutureProvider.autoDispose
    .family<RebalanceExecutionSession?, String>((ref, sessionId) async {
      ref.watch(activeUserIdProvider);
      final gateway = await ref.watch(
        rebalanceExecutionWorkspaceGatewayProvider.future,
      );
      return gateway.session(sessionId);
    });

final rebalanceOwnedAccountsProvider =
    StreamProvider.autoDispose<List<Account>>((ref) async* {
      final owner = ref.watch(activeUserIdProvider);
      if (owner == null || owner.isEmpty) {
        yield const <Account>[];
        return;
      }
      final repository = await ref.watch(accountRepositoryProvider.future);
      yield* repository.watchActiveForOwner(owner);
    });

final rebalanceOwnedSecuritiesProvider =
    StreamProvider.autoDispose<List<Asset>>((ref) async* {
      final owner = ref.watch(activeUserIdProvider);
      if (owner == null || owner.isEmpty) {
        yield const <Asset>[];
        return;
      }
      final repository = await ref.watch(
        securitiesAssetRepositoryProvider.future,
      );
      yield* repository.watchSecuritiesForOwner(
        owner,
        types: kSecuritiesAssetTypes,
      );
    });

/// The rebalance engine instance. Thresholds are user-configurable via
/// [warningThresholdProvider] / [criticalThresholdProvider].
final rebalanceEngineProvider = Provider<RebalanceEngine>((ref) {
  final warning = ref.watch(warningThresholdProvider);
  final critical = ref.watch(criticalThresholdProvider);
  return RebalanceEngine(
    warningThreshold: warning,
    criticalThreshold: critical,
  );
});

/// User-selected allocation scheme preset.
///
/// **Derived** from [riskAppetiteProvider] — there is one user-facing
/// "risk appetite" dial in Settings, and the rebalance preset is just
/// its projection onto allocation space. Callers who want to *change*
/// the selection must write to `riskAppetiteProvider`; this provider
/// is read-only by design.
final selectedSchemeProvider = Provider<AllocationSchemePreset>((ref) {
  return schemePresetFor(ref.watch(riskAppetiteProvider));
});

/// Map [RiskAppetite] → [AllocationSchemePreset]. The two domains are
/// 1:1 (with `moderate` ↔ `balanced` being the only name divergence)
/// so the inverse can be done cheaply in either direction.
AllocationSchemePreset schemePresetFor(RiskAppetite appetite) =>
    switch (appetite) {
      RiskAppetite.conservative => AllocationSchemePreset.conservative,
      RiskAppetite.moderate => AllocationSchemePreset.balanced,
      RiskAppetite.aggressive => AllocationSchemePreset.aggressive,
      RiskAppetite.custom => AllocationSchemePreset.custom,
    };

/// Inverse of [schemePresetFor] — useful for UI surfaces that still
/// think in terms of presets (e.g. the Rebalance page's
/// `_SchemeSelector`) but ultimately want to write the canonical
/// appetite.
RiskAppetite appetiteForScheme(AllocationSchemePreset preset) =>
    switch (preset) {
      AllocationSchemePreset.conservative => RiskAppetite.conservative,
      AllocationSchemePreset.balanced => RiskAppetite.moderate,
      AllocationSchemePreset.aggressive => RiskAppetite.aggressive,
      AllocationSchemePreset.custom => RiskAppetite.custom,
    };

/// Explicit group selection within the selected real portfolio.
final selectedPortfolioRebalanceGroupIdProvider = StateProvider<String?>(
  (ref) => null,
);

final effectiveSelectedPortfolioRebalanceGroupIdProvider = Provider<String?>((
  ref,
) {
  final selectedPortfolioId = ref.watch(
    effectiveSelectedInvestmentPortfolioIdProvider,
  );
  if (selectedPortfolioId == null ||
      selectedPortfolioId == kUnassignedInvestmentPortfolioId) {
    return null;
  }
  final groups = ref.watch(selectedPortfolioRebalanceGroupsProvider);
  if (!groups.hasValue || groups.requireValue.isEmpty) return null;
  final requested = ref.watch(selectedPortfolioRebalanceGroupIdProvider);
  if (requested != null &&
      groups.requireValue.any((group) => group.id == requested)) {
    return requested;
  }
  return groups.requireValue.first.id;
});

final selectedPortfolioRebalanceGroupProvider =
    Provider<AsyncValue<PortfolioRebalanceGroup?>>((ref) {
      final selectedId = ref.watch(
        effectiveSelectedPortfolioRebalanceGroupIdProvider,
      );
      return ref
          .watch(selectedPortfolioRebalanceGroupsProvider)
          .whenData(
            (groups) =>
                groups.where((group) => group.id == selectedId).firstOrNull,
          );
    });

/// Internal target allocation for the selected capital-owning group.
///
/// Virtual all-holdings and unassigned views have no group row, so those two
/// read-only scopes continue to use user-scoped preferences.
final targetAllocationProvider =
    StateNotifierProvider<TargetAllocationController, TargetAllocation>((ref) {
      final scheme = ref.read(selectedSchemeProvider);
      final selectedId = ref.watch(
        effectiveSelectedInvestmentPortfolioIdProvider,
      );
      final group = ref.watch(selectedPortfolioRebalanceGroupProvider).value;
      final ownerUserId = ref.watch(activeUserIdProvider);
      return TargetAllocationController(
        scheme: scheme,
        group: group,
        repository: ref.watch(investmentPortfolioRepositoryProvider.future),
        preferences: ref.watch(sharedPreferencesProvider),
        virtualStorageKey: _virtualTargetAllocationStorageKey(
          ownerUserId: ownerUserId,
          selectedPortfolioId: selectedId,
        ),
      );
    });

String? _virtualTargetAllocationStorageKey({
  required String? ownerUserId,
  required String? selectedPortfolioId,
}) {
  final scope = switch (selectedPortfolioId) {
    null => 'all',
    kUnassignedInvestmentPortfolioId => 'unassigned',
    _ => null,
  };
  if (scope == null) return null;
  return 'naviwealth.rebalance.target_allocation.'
      '${ownerUserId ?? 'local'}.$scope';
}

class TargetAllocationController extends StateNotifier<TargetAllocation> {
  TargetAllocationController({
    required AllocationSchemePreset scheme,
    required PortfolioRebalanceGroup? group,
    required Future<InvestmentPortfolioRepository> repository,
    SharedPreferences? preferences,
    String? virtualStorageKey,
  }) : _scheme = scheme,
       _group = group,
       _repository = repository,
       _preferences = preferences,
       _virtualStorageKey = virtualStorageKey,
       super(_load(group, scheme, preferences, virtualStorageKey));

  final AllocationSchemePreset _scheme;
  PortfolioRebalanceGroup? _group;
  final Future<InvestmentPortfolioRepository> _repository;
  final SharedPreferences? _preferences;
  final String? _virtualStorageKey;

  static TargetAllocation _load(
    PortfolioRebalanceGroup? group,
    AllocationSchemePreset scheme,
    SharedPreferences? preferences,
    String? virtualStorageKey,
  ) {
    if (group != null) return group.internalTarget;
    final raw = virtualStorageKey == null
        ? null
        : preferences?.getString(virtualStorageKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return TargetAllocation.fromJson(map);
      } catch (_) {
        // Fall through to preset.
      }
    }
    return allocationScheme(scheme);
  }

  Future<void> update(TargetAllocation allocation) async {
    state = allocation;
    await _persist(allocation);
  }

  /// Reset to the current scheme's default weights.
  Future<void> resetToScheme() async {
    final preset = allocationScheme(_scheme);
    state = preset;
    await _persist(preset);
  }

  Future<void> _persist(TargetAllocation allocation) async {
    final group = _group;
    if (group == null) {
      final preferences = _preferences;
      final storageKey = _virtualStorageKey;
      if (preferences != null && storageKey != null) {
        await preferences.setString(
          storageKey,
          jsonEncode(allocation.toJson()),
        );
      }
      return;
    }
    _group = await (await _repository).updateGroup(
      group.copyWith(internalTarget: allocation),
    );
  }
}

/// Warning threshold (default 5%).
final warningThresholdProvider =
    StateNotifierProvider<ThresholdController, double>((ref) {
      return ThresholdController(
        ref.watch(sharedPreferencesProvider),
        key: _kWarningThresholdKey,
        defaultValue: 0.05,
      );
    });

/// Critical threshold (default 10%).
final criticalThresholdProvider =
    StateNotifierProvider<ThresholdController, double>((ref) {
      return ThresholdController(
        ref.watch(sharedPreferencesProvider),
        key: _kCriticalThresholdKey,
        defaultValue: 0.10,
      );
    });

class ThresholdController extends StateNotifier<double> {
  ThresholdController(
    this._prefs, {
    required this.key,
    required this.defaultValue,
  }) : super(_prefs.getDouble(key) ?? defaultValue);

  final SharedPreferences _prefs;
  final String key;
  final double defaultValue;

  Future<void> set(double value) async {
    state = value;
    await _prefs.setDouble(key, value);
  }
}

final hierarchicalRebalanceEngineProvider =
    Provider<HierarchicalRebalanceEngine>((ref) {
      return HierarchicalRebalanceEngine(
        internalEngine: ref.watch(rebalanceEngineProvider),
      );
    });

final universeRebalanceEngineProvider = Provider<UniverseRebalanceEngine>((
  ref,
) {
  return UniverseRebalanceEngine(
    portfolioEngine: ref.watch(hierarchicalRebalanceEngineProvider),
  );
});

final allPortfolioGroupSnapshotsProvider =
    FutureProvider.autoDispose<Map<String, Map<String, DashboardSnapshot>>>((
      ref,
    ) async {
      final scopes = await ref.watch(allPortfolioScopedHoldingsProvider.future);
      final groups = await ref.watch(portfolioRebalanceGroupsProvider.future);
      final assets = await ref.watch(allAssetsStreamProvider.future);
      final dashboard = await ref.watch(dashboardSnapshotProvider.future);
      return Map<String, Map<String, DashboardSnapshot>>.unmodifiable({
        for (final portfolioEntry in scopes.entries)
          portfolioEntry.key: Map<String, DashboardSnapshot>.unmodifiable({
            for (final group in groups.where(
              (item) => item.portfolioId == portfolioEntry.key,
            ))
              group.id: _buildRebalanceSnapshot(
                holdings:
                    portfolioEntry.value.snapshotsByGroup[group.id] ?? const {},
                cashAssignments: portfolioEntry.value.cashAssignments
                    .where(
                      (assignment) => assignment.rebalanceGroupId == group.id,
                    )
                    .toList(growable: false),
                assets: assets,
                dashboard: dashboard,
              ),
          }),
      });
    });

/// Per-group snapshots preserve exclusive capital ownership. Cash assignments
/// are valued from the dashboard account item and never copied into overlays.
final rebalancePortfolioGroupSnapshotsProvider =
    FutureProvider.autoDispose<Map<String, DashboardSnapshot>>((ref) async {
      final selectedId = ref.watch(
        effectiveSelectedInvestmentPortfolioIdProvider,
      );
      if (selectedId == null ||
          selectedId == kUnassignedInvestmentPortfolioId) {
        return const {};
      }
      final allSnapshots = await ref.watch(
        allPortfolioGroupSnapshotsProvider.future,
      );
      return allSnapshots[selectedId] ?? const {};
    });

/// Snapshot used by the existing single-group execution workspace.
final rebalancePortfolioSnapshotProvider =
    FutureProvider.autoDispose<DashboardSnapshot>((ref) async {
      final selectedId = ref.watch(
        effectiveSelectedInvestmentPortfolioIdProvider,
      );
      if (selectedId == null) {
        return ref.watch(dashboardSnapshotProvider.future);
      }
      if (selectedId != kUnassignedInvestmentPortfolioId) {
        final groupId = ref.watch(
          effectiveSelectedPortfolioRebalanceGroupIdProvider,
        );
        final snapshots = await ref.watch(
          rebalancePortfolioGroupSnapshotsProvider.future,
        );
        final dashboard = await ref.watch(dashboardSnapshotProvider.future);
        return snapshots[groupId] ?? _emptySnapshot(dashboard);
      }
      final scopedFuture = ref.watch(scopedPortfolioHoldingsProvider.future);
      final assetsFuture = ref.watch(allAssetsStreamProvider.future);
      final dashboardFuture = ref.watch(dashboardSnapshotProvider.future);
      final scoped = await scopedFuture;
      final assets = await assetsFuture;
      final dashboard = await dashboardFuture;
      return _buildRebalanceSnapshot(
        holdings: scoped.snapshots,
        cashAssignments: const [],
        assets: assets,
        dashboard: dashboard,
      );
    });

final hierarchicalRebalancePlanProvider = Provider<PortfolioRebalancePlan?>((
  ref,
) {
  final selectedId = ref.watch(effectiveSelectedInvestmentPortfolioIdProvider);
  if (selectedId == null || selectedId == kUnassignedInvestmentPortfolioId) {
    return null;
  }
  final groups = ref.watch(selectedPortfolioRebalanceGroupsProvider).value;
  final snapshots = ref.watch(rebalancePortfolioGroupSnapshotsProvider).value;
  final dashboard = ref.watch(dashboardSnapshotProvider).value;
  if (groups == null || snapshots == null || dashboard == null) return null;
  return ref
      .watch(hierarchicalRebalanceEngineProvider)
      .compute(
        target: PortfolioRebalanceTarget(groups: groups),
        snapshotsByGroup: snapshots,
        baseCurrency: dashboard.baseCurrency,
      );
});

final universeRebalancePlanProvider = Provider<UniverseRebalancePlan?>((ref) {
  final universe = ref.watch(activeRebalanceUniverseProvider).value;
  final targets = ref.watch(activeUniversePortfolioTargetsProvider).value;
  final portfolios = ref.watch(investmentPortfoliosProvider).value;
  final groups = ref.watch(portfolioRebalanceGroupsProvider).value;
  final snapshots = ref.watch(allPortfolioGroupSnapshotsProvider).value;
  if (universe == null ||
      targets == null ||
      targets.isEmpty ||
      portfolios == null ||
      groups == null ||
      snapshots == null) {
    return null;
  }
  final portfoliosById = {
    for (final portfolio in portfolios) portfolio.id: portfolio,
  };
  if (targets.any(
    (target) => !portfoliosById.containsKey(target.portfolioId),
  )) {
    return null;
  }
  final groupsByPortfolio = {
    for (final portfolio in portfolios)
      portfolio.id: groups
          .where((group) => group.portfolioId == portfolio.id)
          .toList(growable: false),
  };
  return ref
      .watch(universeRebalanceEngineProvider)
      .compute(
        target: UniverseAllocationTarget(
          universe: universe,
          portfolios: targets,
        ),
        portfoliosById: portfoliosById,
        groupsByPortfolio: groupsByPortfolio,
        snapshotsByPortfolioGroup: snapshots,
      );
});

final rebalancePlanProvider = Provider<RebalancePlan?>((ref) {
  final selectedId = ref.watch(effectiveSelectedInvestmentPortfolioIdProvider);
  if (selectedId != null && selectedId != kUnassignedInvestmentPortfolioId) {
    final groupId = ref.watch(
      effectiveSelectedPortfolioRebalanceGroupIdProvider,
    );
    return ref
        .watch(hierarchicalRebalancePlanProvider)
        ?.groups
        .where((group) => group.group.id == groupId)
        .firstOrNull
        ?.internalPlan;
  }
  final snapshotAsync = ref.watch(rebalancePortfolioSnapshotProvider);
  final target = ref.watch(targetAllocationProvider);
  final engine = ref.watch(rebalanceEngineProvider);

  final snapshot = snapshotAsync.value;
  if (snapshot == null || snapshot.isEmpty) return null;

  return engine.compute(snapshot: snapshot, target: target);
});

DashboardSnapshot _buildRebalanceSnapshot({
  required Map<String, HoldingSnapshot> holdings,
  required List<PortfolioCapitalAssignment> cashAssignments,
  required List<Asset> assets,
  required DashboardSnapshot dashboard,
}) {
  final assetById = {for (final asset in assets) asset.id: asset};
  final dashboardItemById = {
    for (final allocation in dashboard.allocations)
      for (final item in allocation.items) item.id: item,
  };
  final itemsByCategory = <AssetCategory, List<CategoryItem>>{};
  for (final holding in holdings.values) {
    final asset = assetById[holding.assetId];
    if (asset == null) continue;
    final category = categoryForAssetType(asset.type);
    itemsByCategory
        .putIfAbsent(category, () => <CategoryItem>[])
        .add(
          CategoryItem(
            id: holding.assetId,
            name: asset.name?.trim().isNotEmpty == true
                ? asset.name!.trim()
                : asset.symbol,
            subtitle: asset.symbol,
            valueInBase: Money(
              holding.marketValueInBase,
              dashboard.baseCurrency,
            ),
            nativeAmount: holding.marketValueInAssetCurrency,
            nativeCurrency: holding.assetCurrency,
          ),
        );
  }
  for (final assignment in cashAssignments) {
    final amount = assignment.amount!;
    final currency = assignment.currency!;
    final accountItem = dashboardItemById[assignment.sourceId];
    final amountInBase = _cashValueInBase(
      amount: amount,
      currency: currency,
      accountItem: accountItem,
      baseCurrency: dashboard.baseCurrency,
    );
    if (amountInBase == null) continue;
    itemsByCategory
        .putIfAbsent(AssetCategory.cash, () => <CategoryItem>[])
        .add(
          CategoryItem(
            id: assignment.id,
            name: accountItem?.name ?? currency,
            subtitle: accountItem?.subtitle,
            valueInBase: Money(amountInBase, dashboard.baseCurrency),
            nativeAmount: amount,
            nativeCurrency: currency,
          ),
        );
  }
  final allocations = <CategoryAllocation>[];
  var total = Decimal.zero;
  for (final entry in itemsByCategory.entries) {
    final categoryTotal = entry.value.fold<Decimal>(
      Decimal.zero,
      (sum, item) => sum + item.valueInBase.amount,
    );
    total += categoryTotal;
    allocations.add(
      CategoryAllocation(
        category: entry.key,
        totalInBase: Money(categoryTotal, dashboard.baseCurrency),
        items: List.unmodifiable(entry.value),
      ),
    );
  }
  final totalMoney = Money(total, dashboard.baseCurrency);
  return DashboardSnapshot(
    asOf: DateTime.now().toUtc(),
    baseCurrency: dashboard.baseCurrency,
    allocations: List.unmodifiable(allocations),
    totalAssets: totalMoney,
    totalLiabilities: Money.zero(dashboard.baseCurrency),
    netWorth: totalMoney,
  );
}

Decimal? _cashValueInBase({
  required Decimal amount,
  required String currency,
  required CategoryItem? accountItem,
  required String baseCurrency,
}) {
  if (currency == baseCurrency) return amount;
  final nativeAmount = accountItem?.nativeAmount;
  if (nativeAmount == null ||
      nativeAmount == Decimal.zero ||
      accountItem == null) {
    return null;
  }
  return (amount * accountItem.valueInBase.amount / nativeAmount).toDecimal(
    scaleOnInfinitePrecision: 8,
  );
}

DashboardSnapshot _emptySnapshot(DashboardSnapshot source) {
  final zero = Money.zero(source.baseCurrency);
  return DashboardSnapshot(
    asOf: DateTime.now().toUtc(),
    baseCurrency: source.baseCurrency,
    allocations: const [],
    totalAssets: zero,
    totalLiabilities: zero,
    netWorth: zero,
  );
}
