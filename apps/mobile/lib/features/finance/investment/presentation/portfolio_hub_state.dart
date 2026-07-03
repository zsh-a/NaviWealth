part of 'portfolio_hub_page.dart';

final portfolioHubProvider =
    AsyncNotifierProvider<PortfolioHubNotifier, PortfolioHubState>(
      PortfolioHubNotifier.new,
    );

class PortfolioHubNotifier
    extends ConventionalAsyncNotifier<PortfolioHubState> {
  @override
  Future<PortfolioHubState> fetch() async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final yearStart = DateTime.utc(today.year, 1, 1);

    final holdings = await ref.watch(holdingsSnapshotProvider.future);
    final assets = await ref.watch(allAssetsStreamProvider.future);
    final accounts = await ref.watch(accountsStreamProvider.future);
    final baseCurrency = ref.watch(holdingBaseCurrencyProvider);
    final holdingService = await ref.watch(holdingServiceProvider.future);
    final returnService = await ref.watch(
      portfolioReturnServiceProvider.future,
    );
    final lots = await holdingService.lotsAt(now);
    final returns = await returnService.compute(from: yearStart, to: today);
    final realized = await ref.watch(realizedPnlProvider.future);
    final dividendForecast = await ref.watch(
      dividendForecast12mProvider.future,
    );
    final dividendCenter = await ref.watch(
      dividendCenterSnapshotProvider.future,
    );
    final corporateActions = ref.watch(dividendForecastDeclaredActionsProvider);

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
      realizedPnl: realized,
      dividendForecast: dividendForecast,
      dividendEvents: dividendCenter.events,
      corporateActions: corporateActions,
    );
  }
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
    required this.realizedPnl,
    required this.dividendForecast,
    required this.dividendEvents,
    required this.corporateActions,
  });

  final List<PortfolioHoldingRow> holdings;
  final List<Lot> lots;
  final Map<String, Account> accountById;
  final String baseCurrency;
  final Decimal marketValueInBase;
  final Decimal costBasisInBase;
  final Decimal unrealizedPnlInBase;
  final PortfolioReturnResult ytdReturn;
  final List<RealizedPnL> realizedPnl;
  final ProjectedDividend dividendForecast;
  final List<DividendCenterEvent> dividendEvents;
  final List<CorporateAction> corporateActions;

  double? get xirrRatio => ytdReturn.displayReturn;

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
            holdingId: lot.assetId,
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
            holdingId: row.assetId,
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
  final Set<String> holdingIds = {};
  Decimal marketValue = Decimal.zero;
  Decimal costBasis = Decimal.zero;

  void add({
    required Decimal marketValue,
    required Decimal costBasis,
    required String holdingId,
  }) {
    this.marketValue += marketValue;
    this.costBasis += costBasis;
    holdingIds.add(holdingId);
  }

  PortfolioGroupRow toRow({required Decimal totalMarketValue}) {
    final weight = totalMarketValue.sign <= 0
        ? Decimal.zero
        : (marketValue / totalMarketValue).toDecimal(
            scaleOnInfinitePrecision: 8,
          );
    return PortfolioGroupRow(
      id: id,
      title: title,
      subtitle: subtitle,
      baseCurrency: baseCurrency,
      marketValueInBase: marketValue,
      costBasisInBase: costBasis,
      unrealizedPnlInBase: marketValue - costBasis,
      weight: weight,
      holdingsCount: holdingIds.length,
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
