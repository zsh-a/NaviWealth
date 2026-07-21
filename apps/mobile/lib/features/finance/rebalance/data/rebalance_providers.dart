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
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../design_system/preferences/theme_preferences.dart';
import '../application/rebalance_execution_coordinator.dart';
import '../application/rebalance_execution_workspace_gateway.dart';
import '../application/rebalance_trade_validation.dart';
import '../domain/allocation_schemes.dart';
import '../domain/rebalance_engine.dart';
import '../domain/rebalance_execution.dart';
import '../domain/rebalance_models.dart';
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

/// Target allocation for the currently selected logical portfolio.
///
/// The virtual all-holdings and unassigned views use the risk preset as an
/// ephemeral target. Persisted targets live on `investment_portfolios`, so
/// switching portfolios also switches the rebalance policy.
final targetAllocationProvider =
    StateNotifierProvider<TargetAllocationController, TargetAllocation>((ref) {
      final scheme = ref.read(selectedSchemeProvider);
      final portfolio = ref.watch(selectedInvestmentPortfolioProvider).value;
      return TargetAllocationController(
        scheme: scheme,
        portfolio: portfolio,
        repository: ref.watch(investmentPortfolioRepositoryProvider.future),
      );
    });

class TargetAllocationController extends StateNotifier<TargetAllocation> {
  TargetAllocationController({
    required AllocationSchemePreset scheme,
    required InvestmentPortfolio? portfolio,
    required Future<InvestmentPortfolioRepository> repository,
  }) : _scheme = scheme,
       _portfolio = portfolio,
       _repository = repository,
       super(_load(portfolio, scheme));

  final AllocationSchemePreset _scheme;
  InvestmentPortfolio? _portfolio;
  final Future<InvestmentPortfolioRepository> _repository;

  static TargetAllocation _load(
    InvestmentPortfolio? portfolio,
    AllocationSchemePreset scheme,
  ) {
    final raw = portfolio?.targetAllocationJson;
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
    final portfolio = _portfolio;
    if (portfolio == null) return;
    final updated = portfolio.copyWith(
      targetAllocationJson: jsonEncode(allocation.toJson()),
    );
    _portfolio = await (await _repository).update(updated);
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

/// The computed rebalance plan. Reactively recomputes when the dashboard
/// snapshot or target allocation changes.
final rebalancePortfolioSnapshotProvider =
    FutureProvider.autoDispose<DashboardSnapshot>((ref) async {
      final selectedId = ref.watch(
        effectiveSelectedInvestmentPortfolioIdProvider,
      );
      if (selectedId == null) {
        return ref.watch(dashboardSnapshotProvider.future);
      }
      final scopedFuture = ref.watch(scopedPortfolioHoldingsProvider.future);
      final assetsFuture = ref.watch(allAssetsStreamProvider.future);
      final dashboardFuture = ref.watch(dashboardSnapshotProvider.future);
      final scoped = await scopedFuture;
      final assets = await assetsFuture;
      final dashboard = await dashboardFuture;
      final assetById = {for (final asset in assets) asset.id: asset};
      final itemsByCategory = <AssetCategory, List<CategoryItem>>{};
      for (final holding in scoped.snapshots.values) {
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
    });

final rebalancePlanProvider = Provider<RebalancePlan?>((ref) {
  final snapshotAsync = ref.watch(rebalancePortfolioSnapshotProvider);
  final target = ref.watch(targetAllocationProvider);
  final engine = ref.watch(rebalanceEngineProvider);

  final snapshot = snapshotAsync.value;
  if (snapshot == null || snapshot.isEmpty) return null;

  return engine.compute(snapshot: snapshot, target: target);
});
