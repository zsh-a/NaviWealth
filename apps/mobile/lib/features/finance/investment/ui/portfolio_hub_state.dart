part of 'portfolio_hub_page.dart';

/// Positions / allocation / summary — the always-visible hub surface.
final portfolioHubCoreProvider =
    AsyncNotifierProvider<PortfolioHubCoreNotifier, PortfolioHubState>(
      PortfolioHubCoreNotifier.new,
    );

/// Realized PnL / dividends / corporate actions — only watched on Insights.
final portfolioHubInsightsProvider =
    AsyncNotifierProvider<
      PortfolioHubInsightsNotifier,
      PortfolioHubInsightsState
    >(PortfolioHubInsightsNotifier.new);

/// Page-level alias so existing tests and call sites keep a single entrypoint.
final portfolioHubProvider = portfolioHubCoreProvider;

/// Test/legacy alias for the core notifier type.
typedef PortfolioHubNotifier = PortfolioHubCoreNotifier;

/// Summary strip only — [select] so holdings-list churn does not rebuild
/// the hero metrics when the numeric totals are unchanged.
final portfolioHubSummarySliceProvider =
    Provider<AsyncValue<PortfolioHubSummarySlice>>((ref) {
      return ref.watch(
        portfolioHubCoreProvider.select((async) {
          return async.whenData(PortfolioHubSummarySlice.fromState);
        }),
      );
    });

/// Holdings + lots slice for positions / allocation.
final portfolioHubHoldingsSliceProvider =
    Provider<AsyncValue<PortfolioHubHoldingsSlice>>((ref) {
      return ref.watch(
        portfolioHubCoreProvider.select((async) {
          return async.whenData(PortfolioHubHoldingsSlice.fromState);
        }),
      );
    });

/// Numeric hero metrics for the portfolio summary card.
class PortfolioHubSummarySlice {
  const PortfolioHubSummarySlice({
    required this.baseCurrency,
    required this.marketValueInBase,
    required this.costBasisInBase,
    required this.unrealizedPnlInBase,
    required this.xirrRatio,
  });

  factory PortfolioHubSummarySlice.fromState(PortfolioHubState state) {
    return PortfolioHubSummarySlice(
      baseCurrency: state.baseCurrency,
      marketValueInBase: state.marketValueInBase,
      costBasisInBase: state.costBasisInBase,
      unrealizedPnlInBase: state.unrealizedPnlInBase,
      xirrRatio: state.xirrRatio,
    );
  }

  final String baseCurrency;
  final Decimal marketValueInBase;
  final Decimal costBasisInBase;
  final Decimal unrealizedPnlInBase;
  final double? xirrRatio;

  @override
  bool operator ==(Object other) =>
      other is PortfolioHubSummarySlice &&
      other.baseCurrency == baseCurrency &&
      other.marketValueInBase == marketValueInBase &&
      other.costBasisInBase == costBasisInBase &&
      other.unrealizedPnlInBase == unrealizedPnlInBase &&
      other.xirrRatio == xirrRatio;

  @override
  int get hashCode => Object.hash(
    baseCurrency,
    marketValueInBase,
    costBasisInBase,
    unrealizedPnlInBase,
    xirrRatio,
  );
}

/// Positions / allocation inputs without summary-only noise.
class PortfolioHubHoldingsSlice {
  const PortfolioHubHoldingsSlice({
    required this.holdings,
    required this.lots,
    required this.accountById,
    required this.baseCurrency,
    required this.marketValueInBase,
  });

  factory PortfolioHubHoldingsSlice.fromState(PortfolioHubState state) {
    return PortfolioHubHoldingsSlice(
      holdings: state.holdings,
      lots: state.lots,
      accountById: state.accountById,
      baseCurrency: state.baseCurrency,
      marketValueInBase: state.marketValueInBase,
    );
  }

  final List<PortfolioHoldingRow> holdings;
  final List<Lot> lots;
  final Map<String, Account> accountById;
  final String baseCurrency;
  final Decimal marketValueInBase;

  /// Reuse grouping logic via a thin adapter state.
  PortfolioHubState asGroupingState(PortfolioReturnResult ytdReturn) {
    return PortfolioHubState(
      holdings: holdings,
      lots: lots,
      accountById: accountById,
      baseCurrency: baseCurrency,
      marketValueInBase: marketValueInBase,
      costBasisInBase: Decimal.zero,
      unrealizedPnlInBase: Decimal.zero,
      ytdReturn: ytdReturn,
      portfolioScoped: false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PortfolioHubHoldingsSlice &&
      identical(other.holdings, holdings) &&
      identical(other.lots, lots) &&
      identical(other.accountById, accountById) &&
      other.baseCurrency == baseCurrency &&
      other.marketValueInBase == marketValueInBase;

  @override
  int get hashCode => Object.hash(
    identityHashCode(holdings),
    identityHashCode(lots),
    identityHashCode(accountById),
    baseCurrency,
    marketValueInBase,
  );
}

class PortfolioHubCoreNotifier
    extends ConventionalAsyncNotifier<PortfolioHubState> {
  @override
  Future<PortfolioHubState> fetch() async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final yearStart = DateTime.utc(today.year, 1, 1);

    // Subscribe to the complete holdings graph before the first async gap
    // so concurrent upstream emissions cannot partially rebuild this tree.
    final scopedHoldingsFuture = ref.watch(
      scopedPortfolioHoldingsProvider.future,
    );
    final assetsFuture = ref.watch(allAssetsStreamProvider.future);
    final accountsFuture = ref.watch(accountsStreamProvider.future);
    final baseCurrency = ref.watch(holdingBaseCurrencyProvider);
    final selectedPortfolioId = ref.watch(
      effectiveSelectedInvestmentPortfolioIdProvider,
    );
    final returnServiceFuture = ref.watch(
      portfolioReturnServiceProvider.future,
    );

    final scopedHoldings = await scopedHoldingsFuture;
    final holdings = scopedHoldings.snapshots;
    final assets = await assetsFuture;
    final accounts = await accountsFuture;
    final returnService = await returnServiceFuture;
    final lots = scopedHoldings.lots;
    final returns = await returnService.compute(from: yearStart, to: today);

    final assetById = {for (final asset in assets) asset.id: asset};
    final accountById = {for (final account in accounts) account.id: account};
    final rows = [
      for (final entry in holdings.entries)
        PortfolioHoldingRow.fromSnapshot(
          snapshot: entry.value,
          asset: assetById[entry.key],
        ),
    ]..sort((a, b) => b.marketValueInBase.compareTo(a.marketValueInBase));

    final marketValue = _sum(rows.map((row) => row.marketValueInBase));
    final costBasis = _sum(rows.map((row) => row.costBasisInBase));
    final unrealizedPnl = _sum(rows.map((row) => row.unrealizedPnlInBase));
    return PortfolioHubState(
      holdings: rows,
      lots: lots,
      accountById: accountById,
      baseCurrency: baseCurrency,
      marketValueInBase: marketValue,
      costBasisInBase: costBasis,
      unrealizedPnlInBase: unrealizedPnl,
      ytdReturn: returns,
      portfolioScoped: selectedPortfolioId != null,
    );
  }
}

class PortfolioHubInsightsNotifier
    extends ConventionalAsyncNotifier<PortfolioHubInsightsState> {
  @override
  Future<PortfolioHubInsightsState> fetch() async {
    // Subscribe before the first await (same partial-rebuild guard as core).
    final realizedFuture = ref.watch(realizedPnlProvider.future);
    final dividendForecastFuture = ref.watch(
      dividendForecast12mProvider.future,
    );
    final dividendCenterFuture = ref.watch(
      dividendCenterSnapshotProvider.future,
    );
    final corporateActions = ref.watch(dividendForecastDeclaredActionsProvider);
    final scopedHoldingsFuture = ref.watch(
      scopedPortfolioHoldingsProvider.future,
    );
    final selectedPortfolioId = ref.watch(
      effectiveSelectedInvestmentPortfolioIdProvider,
    );

    final realized = await realizedFuture;
    final dividendForecast = await dividendForecastFuture;
    final dividendCenter = await dividendCenterFuture;
    final scopedHoldings = await scopedHoldingsFuture;
    final scopedAssetIds = scopedHoldings.snapshots.keys.toSet();
    final scopedLotIds = scopedHoldings.lots.map((lot) => lot.id).toSet();
    bool includesLot(String lotId) {
      if (selectedPortfolioId == null) return true;
      return scopedLotIds.contains(lotId);
    }

    return PortfolioHubInsightsState(
      realizedPnl: realized.where((item) => includesLot(item.lotId)).toList(),
      dividendForecast: dividendForecast,
      dividendEvents: selectedPortfolioId == null
          ? dividendCenter.events
          : dividendCenter.events
                .where((event) => scopedAssetIds.contains(event.assetId))
                .toList(),
      corporateActions: selectedPortfolioId == null
          ? corporateActions
          : corporateActions
                .where((action) => scopedAssetIds.contains(action.assetId))
                .toList(),
    );
  }
}

class PortfolioHubInsightsState {
  const PortfolioHubInsightsState({
    required this.realizedPnl,
    required this.dividendForecast,
    required this.dividendEvents,
    required this.corporateActions,
  });

  final List<RealizedPnL> realizedPnl;
  final ProjectedDividend dividendForecast;
  final List<DividendCenterEvent> dividendEvents;
  final List<CorporateAction> corporateActions;
}

class PortfolioHubState {
  const PortfolioHubState({
    required this.holdings,
    required this.lots,
    required this.accountById,
    required this.baseCurrency,
    required this.marketValueInBase,
    required this.costBasisInBase,
    required this.unrealizedPnlInBase,
    required this.ytdReturn,
    this.portfolioScoped = false,
  });

  final List<PortfolioHoldingRow> holdings;
  final List<Lot> lots;
  final Map<String, Account> accountById;
  final String baseCurrency;
  final Decimal marketValueInBase;
  final Decimal costBasisInBase;
  final Decimal unrealizedPnlInBase;
  final PortfolioReturnResult ytdReturn;
  final bool portfolioScoped;

  double? get xirrRatio => portfolioScoped ? null : ytdReturn.displayReturn;

  List<PortfolioGroupRow> groupsFor(
    PortfolioHubView view,
    AppLocalizations l10n,
  ) {
    switch (view) {
      case PortfolioHubView.account:
        return _accountGroups(l10n);
      case PortfolioHubView.currency:
        return _groupBy(
          idOf: (row) => row.assetCurrency,
          titleOf: (row) => row.assetCurrency,
          subtitleOf: (_) => l10n.portfolioHubCurrencyGroupSubtitle,
        );
      case PortfolioHubView.assetClass:
        return _groupBy(
          idOf: (row) => row.assetType.name,
          titleOf: (row) => row.assetTypeLabel(l10n),
          subtitleOf: (_) => l10n.portfolioHubAssetClassGroupSubtitle,
        );
    }
  }

  List<PortfolioGroupRow> _accountGroups(AppLocalizations l10n) {
    final holdingByAsset = {for (final row in holdings) row.assetId: row};
    final assetQuantity = <String, Decimal>{};
    final assetCost = <String, Decimal>{};
    for (final lot in lots.where((lot) => !lot.isClosed)) {
      assetQuantity.update(
        lot.assetId,
        (value) => value + lot.remainingQuantity,
        ifAbsent: () => lot.remainingQuantity,
      );
      assetCost.update(
        lot.assetId,
        (value) => value + lot.remainingCost,
        ifAbsent: () => lot.remainingCost,
      );
    }

    final buckets = <String, _GroupAccumulator>{};
    for (final lot in lots.where((lot) => !lot.isClosed)) {
      final holding = holdingByAsset[lot.assetId];
      if (holding == null) continue;
      final totalQty = assetQuantity[lot.assetId] ?? Decimal.zero;
      if (totalQty.sign <= 0) continue;

      final qtyRatio = (lot.remainingQuantity / totalQty).toDecimal(
        scaleOnInfinitePrecision: 12,
      );
      final totalCost = assetCost[lot.assetId] ?? Decimal.zero;
      final costRatio = totalCost.sign <= 0
          ? qtyRatio
          : (lot.remainingCost / totalCost).toDecimal(
              scaleOnInfinitePrecision: 12,
            );
      final marketValue = holding.marketValueInBase * qtyRatio;
      final costBasis = holding.costBasisInBase * costRatio;
      final account = accountById[lot.accountId];
      final title = account?.name ?? l10n.portfolioHubUnknownAccount;
      final subtitle = account?.institution?.isNotEmpty == true
          ? account!.institution!
          : l10n.portfolioHubAccountGroupSubtitle;
      buckets
          .putIfAbsent(
            lot.accountId,
            () => _GroupAccumulator(
              id: lot.accountId,
              title: title,
              subtitle: subtitle,
              baseCurrency: baseCurrency,
            ),
          )
          .add(
            marketValue: marketValue,
            costBasis: costBasis,
            quantity: lot.remainingQuantity,
            holding: holding,
          );
    }
    return _sortedGroups(buckets.values);
  }

  List<PortfolioGroupRow> _groupBy({
    required String Function(PortfolioHoldingRow row) idOf,
    required String Function(PortfolioHoldingRow row) titleOf,
    required String Function(PortfolioHoldingRow row) subtitleOf,
  }) {
    final buckets = <String, _GroupAccumulator>{};
    for (final row in holdings) {
      final id = idOf(row);
      buckets
          .putIfAbsent(
            id,
            () => _GroupAccumulator(
              id: id,
              title: titleOf(row),
              subtitle: subtitleOf(row),
              baseCurrency: baseCurrency,
            ),
          )
          .add(
            marketValue: row.marketValueInBase,
            costBasis: row.costBasisInBase,
            quantity: row.quantity,
            holding: row,
          );
    }
    return _sortedGroups(buckets.values);
  }

  List<PortfolioGroupRow> _sortedGroups(Iterable<_GroupAccumulator> groups) {
    return [
      for (final group in groups)
        group.toRow(totalMarketValue: marketValueInBase),
    ]..sort((a, b) => b.marketValueInBase.compareTo(a.marketValueInBase));
  }
}

class PortfolioHoldingRow {
  const PortfolioHoldingRow({
    required this.assetId,
    required this.title,
    required this.subtitle,
    required this.assetType,
    required this.assetCurrency,
    required this.quantity,
    required this.marketValueInBase,
    required this.costBasisInBase,
    required this.unrealizedPnlInBase,
    required this.weight,
    required this.baseCurrency,
  });

  factory PortfolioHoldingRow.fromSnapshot({
    required HoldingSnapshot snapshot,
    required Asset? asset,
  }) {
    final title = asset?.name?.isNotEmpty == true
        ? asset!.name!
        : asset?.symbol ?? snapshot.assetId;
    final code = asset?.symbol ?? snapshot.assetId;
    return PortfolioHoldingRow(
      assetId: snapshot.assetId,
      title: title,
      subtitle: _sameDisplayText(title, code) ? '' : code,
      assetType: asset?.type ?? AssetType.custom,
      assetCurrency: snapshot.assetCurrency,
      quantity: snapshot.quantity,
      marketValueInBase: snapshot.marketValueInBase,
      costBasisInBase: snapshot.costBasisInBase,
      unrealizedPnlInBase: snapshot.unrealizedPnlInBase,
      weight: snapshot.weight,
      baseCurrency: snapshot.baseCurrency,
    );
  }

  final String assetId;
  final String title;
  final String subtitle;
  final AssetType assetType;
  final String assetCurrency;
  final Decimal quantity;
  final Decimal marketValueInBase;
  final Decimal costBasisInBase;
  final Decimal unrealizedPnlInBase;
  final Decimal weight;
  final String baseCurrency;

  String assetTypeLabel(AppLocalizations l10n) {
    switch (assetType) {
      case AssetType.stock:
        return l10n.portfolioHubAssetTypeStock;
      case AssetType.etf:
        return l10n.portfolioHubAssetTypeEtf;
      case AssetType.mutualFund:
        return l10n.portfolioHubAssetTypeMutualFund;
      case AssetType.bond:
        return l10n.portfolioHubAssetTypeBond;
      case AssetType.crypto:
        return l10n.portfolioHubAssetTypeCrypto;
      case AssetType.cash:
        return l10n.portfolioHubAssetTypeCash;
      case AssetType.realEstate:
        return l10n.physicalAssetTypeRealEstate;
      case AssetType.vehicle:
        return l10n.physicalAssetTypeVehicle;
      case AssetType.commodity:
        return l10n.portfolioHubAssetTypeCommodity;
      case AssetType.custom:
        return l10n.portfolioHubAssetTypeCustom;
      case AssetType.bankDepositTerm:
        return l10n.portfolioHubAssetTypeBankDepositTerm;
      case AssetType.bankDepositDemand:
        return l10n.portfolioHubAssetTypeBankDepositDemand;
      case AssetType.wealthProduct:
        return l10n.portfolioHubAssetTypeWealthProduct;
    }
  }
}

class PortfolioGroupRow {
  const PortfolioGroupRow({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.baseCurrency,
    required this.marketValueInBase,
    required this.costBasisInBase,
    required this.unrealizedPnlInBase,
    required this.weight,
    required this.holdingsCount,
    required this.holdings,
  });

  final String id;
  final String title;
  final String subtitle;
  final String baseCurrency;
  final Decimal marketValueInBase;
  final Decimal costBasisInBase;
  final Decimal unrealizedPnlInBase;
  final Decimal weight;
  final int holdingsCount;
  final List<PortfolioHoldingRow> holdings;
}

enum PortfolioHubView { account, currency, assetClass }

class _GroupAccumulator {
  _GroupAccumulator({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.baseCurrency,
  });

  final String id;
  final String title;
  final String subtitle;
  final String baseCurrency;
  final Map<String, _GroupHoldingAccumulator> holdingBuckets = {};
  Decimal marketValue = Decimal.zero;
  Decimal costBasis = Decimal.zero;

  void add({
    required Decimal marketValue,
    required Decimal costBasis,
    required Decimal quantity,
    required PortfolioHoldingRow holding,
  }) {
    this.marketValue += marketValue;
    this.costBasis += costBasis;
    holdingBuckets
        .putIfAbsent(
          holding.assetId,
          () => _GroupHoldingAccumulator(holding: holding),
        )
        .add(
          quantity: quantity,
          marketValue: marketValue,
          costBasis: costBasis,
        );
  }

  PortfolioGroupRow toRow({required Decimal totalMarketValue}) {
    final weight = totalMarketValue.sign <= 0
        ? Decimal.zero
        : (marketValue / totalMarketValue).toDecimal(
            scaleOnInfinitePrecision: 8,
          );
    final holdings = [
      for (final bucket in holdingBuckets.values)
        bucket.toRow(groupMarketValue: marketValue),
    ]..sort((a, b) => b.marketValueInBase.compareTo(a.marketValueInBase));
    return PortfolioGroupRow(
      id: id,
      title: title,
      subtitle: subtitle,
      baseCurrency: baseCurrency,
      marketValueInBase: marketValue,
      costBasisInBase: costBasis,
      unrealizedPnlInBase: marketValue - costBasis,
      weight: weight,
      holdingsCount: holdings.length,
      holdings: List.unmodifiable(holdings),
    );
  }
}

class _GroupHoldingAccumulator {
  _GroupHoldingAccumulator({required this.holding});

  final PortfolioHoldingRow holding;
  Decimal quantity = Decimal.zero;
  Decimal marketValue = Decimal.zero;
  Decimal costBasis = Decimal.zero;

  void add({
    required Decimal quantity,
    required Decimal marketValue,
    required Decimal costBasis,
  }) {
    this.quantity += quantity;
    this.marketValue += marketValue;
    this.costBasis += costBasis;
  }

  PortfolioHoldingRow toRow({required Decimal groupMarketValue}) {
    final weight = groupMarketValue.sign <= 0
        ? Decimal.zero
        : (marketValue / groupMarketValue).toDecimal(
            scaleOnInfinitePrecision: 8,
          );
    return PortfolioHoldingRow(
      assetId: holding.assetId,
      title: holding.title,
      subtitle: holding.subtitle,
      assetType: holding.assetType,
      assetCurrency: holding.assetCurrency,
      quantity: quantity,
      marketValueInBase: marketValue,
      costBasisInBase: costBasis,
      unrealizedPnlInBase: marketValue - costBasis,
      weight: weight,
      baseCurrency: holding.baseCurrency,
    );
  }
}

Decimal _sum(Iterable<Decimal> values) {
  var total = Decimal.zero;
  for (final value in values) {
    total += value;
  }
  return total;
}

bool _sameDisplayText(String a, String b) {
  return a.trim().toUpperCase() == b.trim().toUpperCase();
}
