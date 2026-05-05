import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/master_detail_layout.dart';
import '../../app/selection_query.dart';
import '../../core/shortcuts/master_detail_shortcuts.dart';
import '../../data/domain/account.dart';
import '../../data/domain/asset.dart';
import '../../data/domain/enums.dart';
import '../../data/domain/manual_asset_metadata.dart';
import '../../data/repositories/manual_asset_repository.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../home/data/dashboard_providers.dart';
import '../home/domain/dashboard_models.dart';
import '../investment/data/providers.dart';
import '../investment/domain/models/holding_snapshot.dart';
import 'asset_detail_page.dart';
import 'physical/data/physical_asset.dart';
import 'physical/data/providers.dart';
import 'physical/ui/physical_asset_card.dart';

/// Tab body for the Portfolio page's Assets segment. Shows the
/// manual-valuation asset book (cash, deposits, wealth products) grouped
/// by type, plus a "real estate & vehicles" section for non-financial
/// assets.
///
/// At desktop width (≥ 1240) the page renders as a master-detail surface
/// (FIR-106): a 380dp asset list on the left and the asset detail page
/// on the right, driven by the `?selected=` query parameter. Tapping a
/// row at narrower widths still pushes the detail route in the usual
/// way.
///
/// Always embedded inside [PortfolioPage] — no Scaffold/AppBar/FAB.
class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final masterDetail = MasterDetailLayout.shouldUseMasterDetail(
          constraints.maxWidth,
        );
        final selected = selectedQueryOf(context);
        if (masterDetail) {
          final detail = selected == null
              ? const _AssetsDetailEmpty()
              : AssetDetailPage(assetId: selected);
          return MasterDetailLayout(
            master: _AssetsMaster(
              selectedAssetId: selected,
              inMasterDetail: true,
            ),
            detail: detail,
          );
        }
        return const _AssetsMaster(
          selectedAssetId: null,
          inMasterDetail: false,
        );
      },
    );
  }
}

/// The standalone "master" (list) surface — used both as the only column
/// at < 1240dp and as the left pane at ≥ 1240dp.
class _AssetsMaster extends ConsumerWidget {
  const _AssetsMaster({
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manualAsync = ref.watch(manualAssetsStreamProvider);
    final physicalAsync = ref.watch(physicalAssetsListProvider);
    final securitiesAsync = ref.watch(securitiesAssetsStreamProvider);
    final holdingsAsync = ref.watch(holdingsSnapshotProvider);

    final securitiesOrdered = _orderedSecurities(securitiesAsync.value);

    // Build a flat ordered list of all asset IDs for j/k navigation. Mirrors
    // the visual order of the body: manual assets, then securities, then
    // physical, so `j`/`k` traverse the same sequence the user reads.
    final allIds = <String>[
      ...?(manualAsync.value?.map((a) => a.id)),
      ...securitiesOrdered.map((a) => a.id),
      ...?(physicalAsync.value?.map((a) => a.id)),
    ];

    final body = _AssetsBody(
      manualAsync: manualAsync,
      physicalAsync: physicalAsync,
      securitiesAsync: securitiesAsync,
      securities: securitiesOrdered,
      holdings: holdingsAsync.value ?? const <String, HoldingSnapshot>{},
      selectedAssetId: selectedAssetId,
      inMasterDetail: inMasterDetail,
    );

    return MasterDetailShortcuts(
      onSelectNext: allIds.isEmpty
          ? null
          : () => _selectAdjacent(context, allIds, delta: 1),
      onSelectPrevious: allIds.isEmpty
          ? null
          : () => _selectAdjacent(context, allIds, delta: -1),
      child: body,
    );
  }

  /// Move selection by [delta] positions in [allIds], wrapping at boundaries.
  void _selectAdjacent(
    BuildContext context,
    List<String> allIds, {
    required int delta,
  }) {
    if (allIds.isEmpty) return;
    final current = selectedAssetId;
    int nextIndex;
    if (current == null) {
      nextIndex = delta > 0 ? 0 : allIds.length - 1;
    } else {
      final idx = allIds.indexOf(current);
      if (idx < 0) {
        nextIndex = 0;
      } else {
        nextIndex = (idx + delta) % allIds.length;
        if (nextIndex < 0) nextIndex += allIds.length;
      }
    }
    replaceSelectedQuery(context, path: '/portfolio', selected: allIds[nextIndex]);
  }
}

class _AssetsDetailEmpty extends StatelessWidget {
  const _AssetsDetailEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: GlassAppBar(title: Text(l10n.assetsAppBarTitle)),
      body: MasterDetailEmpty(
        icon: Icons.account_balance_wallet_outlined,
        message: l10n.assetsDetailEmpty,
      ),
    );
  }
}

class _AssetsBody extends StatelessWidget {
  const _AssetsBody({
    required this.manualAsync,
    required this.physicalAsync,
    required this.securitiesAsync,
    required this.securities,
    required this.holdings,
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final AsyncValue<List<Asset>> manualAsync;
  final AsyncValue<List<PhysicalAsset>> physicalAsync;
  final AsyncValue<List<Asset>> securitiesAsync;
  final List<Asset> securities;
  final Map<String, HoldingSnapshot> holdings;
  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context) {
    final loading = manualAsync.isLoading ||
        physicalAsync.isLoading ||
        securitiesAsync.isLoading;
    return PageSkeletonShell<void>(
      skeleton: const AssetsListSkeleton(),
      isLoading: loading,
      child: _resolveBody(context),
    );
  }

  Widget _resolveBody(BuildContext context) {
    if (manualAsync.isLoading ||
        physicalAsync.isLoading ||
        securitiesAsync.isLoading) {
      return const AssetsListSkeleton();
    }
    final manualErr = manualAsync.hasError ? manualAsync.error : null;
    final physicalErr = physicalAsync.hasError ? physicalAsync.error : null;
    final securitiesErr =
        securitiesAsync.hasError ? securitiesAsync.error : null;
    if (manualErr != null && physicalErr != null && securitiesErr != null) {
      return Center(
        child: Text(
          AppLocalizations.of(context).assetsLoadError('$manualErr'),
        ),
      );
    }
    final manual = manualAsync.value ?? const <Asset>[];
    final physical = physicalAsync.value ?? const <PhysicalAsset>[];
    if (manual.isEmpty && physical.isEmpty && securities.isEmpty) {
      return const _EmptyHint();
    }
    // Build a flat list of section widgets for lazy construction.
    final sections = <Widget>[
      if (manual.isNotEmpty)
        _ManualAssetsSection(
          assets: manual,
          selectedAssetId: selectedAssetId,
          inMasterDetail: inMasterDetail,
        ),
      if (securities.isNotEmpty)
        _SecuritiesAssetsSection(
          assets: securities,
          holdings: holdings,
          selectedAssetId: selectedAssetId,
          inMasterDetail: inMasterDetail,
        ),
      if (physical.isNotEmpty)
        _PhysicalAssetsSection(
          assets: physical,
          selectedAssetId: selectedAssetId,
        ),
    ];
    return ScrollNotificationHandler(
      child: ListView.builder(
        padding: Spacing.pageMobile.copyWith(
          bottom: Spacing.pageMobile.bottom +
              Spacing.floatingBarClearance +
              MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: sections.length,
        itemBuilder: (context, i) => sections[i],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 48),
            const SizedBox(height: Spacing.s12),
            Text(
              l10n.assetsEmptyHint,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualAssetsSection extends ConsumerWidget {
  const _ManualAssetsSection({
    required this.assets,
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final List<Asset> assets;
  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final valuationsAsync = ref.watch(dashboardManualAssetValuationsProvider);
    final valuationMap = <String, Decimal>{};
    for (final v
        in valuationsAsync.value ?? const <ManualAssetValuation>[]) {
      final value = v.currentValue();
      // Cash can go negative (trade overdraw); always include it.
      // Other manual assets with non-positive values are excluded.
      if (value != null &&
          (value.sign > 0 || v.asset.type == AssetType.cash)) {
        valuationMap[v.asset.id] = value;
      }
    }

    final accountsAsync = ref.watch(accountsStreamProvider);
    final accounts = accountsAsync.value ?? const [];
    final accountById = {for (final a in accounts) a.id: a};

    final grouped = <AssetType, List<Asset>>{};
    for (final a in assets) {
      grouped.putIfAbsent(a.type, () => []).add(a);
    }
    final order = [
      AssetType.cash,
      AssetType.bankDepositDemand,
      AssetType.bankDepositTerm,
      AssetType.wealthProduct,
    ].where(grouped.containsKey).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in order) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: Spacing.s8,
              bottom: Spacing.s8,
            ),
            child: Text(
              manualAssetTypeLabel(l10n, type),
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (type == AssetType.cash)
            _CashAccountGroups(
              cashAssets: grouped[type]!,
              valuationMap: valuationMap,
              accountById: accountById,
              selectedAssetId: selectedAssetId,
              inMasterDetail: inMasterDetail,
            )
          else
            LiquidGlassCard(
              child: Column(
                children: [
                  for (final asset in grouped[type]!)
                    _AssetTile(
                      asset: asset,
                      selected: asset.id == selectedAssetId,
                      heroEnabled: !inMasterDetail,
                      value: valuationMap[asset.id],
                    ),
                ],
              ),
            ),
          const SizedBox(height: Spacing.s12),
        ],
      ],
    );
  }
}

/// Groups cash assets by their parent account for a clearer portfolio view.
///
/// Each account gets a sub-header showing the account name and institution,
/// with individual currency balances listed beneath. This aligns with the
/// double-entry bookkeeping model where each account holds a single currency
/// and cash assets map 1:1 to ledger accounts.
class _CashAccountGroups extends StatelessWidget {
  const _CashAccountGroups({
    required this.cashAssets,
    required this.valuationMap,
    required this.accountById,
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final List<Asset> cashAssets;
  final Map<String, Decimal> valuationMap;
  final Map<String, Account> accountById;
  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context) {
    // Group cash assets by accountId.
    final byAccount = <String, List<Asset>>{};
    final orphanAssets = <Asset>[];
    for (final asset in cashAssets) {
      final meta = ManualAssetMetadata.decode(asset.metadataJson);
      final accountId = meta?.accountId;
      if (accountId != null) {
        byAccount.putIfAbsent(accountId, () => []).add(asset);
      } else {
        orphanAssets.add(asset);
      }
    }

    // Sort account groups: those with known accounts first (by name),
    // orphan assets last.
    final sortedAccountIds = byAccount.keys.toList()
      ..sort((a, b) {
        final aa = accountById[a];
        final bb = accountById[b];
        if (aa == null && bb == null) return 0;
        if (aa == null) return 1;
        if (bb == null) return -1;
        return aa.name.compareTo(bb.name);
      });

    return LiquidGlassCard(
      child: Column(
        children: [
          for (final accountId in sortedAccountIds) ...[
            _AccountGroupHeader(accountId: accountId, account: accountById[accountId]),
            for (final asset in byAccount[accountId]!)
              _AssetTile(
                asset: asset,
                selected: asset.id == selectedAssetId,
                heroEnabled: !inMasterDetail,
                value: valuationMap[asset.id],
              ),
          ],
          for (final asset in orphanAssets)
            _AssetTile(
              asset: asset,
              selected: asset.id == selectedAssetId,
              heroEnabled: !inMasterDetail,
              value: valuationMap[asset.id],
            ),
        ],
      ),
    );
  }
}

/// Sub-header for a group of cash assets under one account.
class _AccountGroupHeader extends StatelessWidget {
  const _AccountGroupHeader({required this.accountId, this.account});

  final String accountId;
  final Account? account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = account?.institution;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s16,
        vertical: Spacing.s8,
      ),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Text(
        subtitle != null && subtitle.isNotEmpty
            ? '${account!.name} · $subtitle'
            : account?.name ?? accountId,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Stable display order for the securities section: type bucket first
/// (stocks → ETFs → funds → bonds → crypto), then symbol within bucket.
/// Drives both the visible list order and the j/k navigation order, so
/// they stay in sync without a second sort step.
const List<AssetType> _kSecuritiesTypeOrder = <AssetType>[
  AssetType.stock,
  AssetType.etf,
  AssetType.mutualFund,
  AssetType.bond,
  AssetType.crypto,
];

List<Asset> _orderedSecurities(List<Asset>? assets) {
  if (assets == null || assets.isEmpty) return const <Asset>[];
  final ordered = [...assets];
  ordered.sort((a, b) {
    final ai = _kSecuritiesTypeOrder.indexOf(a.type);
    final bi = _kSecuritiesTypeOrder.indexOf(b.type);
    final aIdx = ai < 0 ? _kSecuritiesTypeOrder.length : ai;
    final bIdx = bi < 0 ? _kSecuritiesTypeOrder.length : bi;
    if (aIdx != bIdx) return aIdx.compareTo(bIdx);
    return a.symbol.compareTo(b.symbol);
  });
  return ordered;
}

String securitiesAssetTypeLabel(AppLocalizations l10n, AssetType t) {
  return switch (t) {
    AssetType.stock => l10n.assetTypeStock,
    AssetType.etf => l10n.assetTypeEtf,
    AssetType.mutualFund => l10n.assetTypeMutualFund,
    AssetType.bond => l10n.assetTypeBond,
    AssetType.crypto => l10n.assetTypeCrypto,
    _ => t.name,
  };
}

class _SecuritiesAssetsSection extends StatelessWidget {
  const _SecuritiesAssetsSection({
    required this.assets,
    required this.holdings,
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final List<Asset> assets;
  final Map<String, HoldingSnapshot> holdings;
  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grouped = <AssetType, List<Asset>>{};
    for (final a in assets) {
      grouped.putIfAbsent(a.type, () => []).add(a);
    }
    final order = _kSecuritiesTypeOrder
        .where(grouped.containsKey)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in order) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: Spacing.s8,
              bottom: Spacing.s8,
            ),
            child: Text(
              securitiesAssetTypeLabel(l10n, type),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          LiquidGlassCard(
            child: Column(
              children: [
                for (final asset in grouped[type]!)
                  _SecurityTile(
                    asset: asset,
                    snapshot: holdings[asset.id],
                    selected: asset.id == selectedAssetId,
                    heroEnabled: !inMasterDetail,
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.s12),
        ],
      ],
    );
  }
}

class _SecurityTile extends StatelessWidget {
  const _SecurityTile({
    required this.asset,
    required this.snapshot,
    required this.selected,
    required this.heroEnabled,
  });

  final Asset asset;
  final HoldingSnapshot? snapshot;
  final bool selected;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final qty = snapshot?.quantity;
    final mvNative = snapshot?.marketValueInAssetCurrency;
    final displayValue = mvNative;
    final hasQty = qty != null && qty.sign != 0;
    final qtyLabel = hasQty
        ? l10n.securitiesHoldingQuantity('$qty')
        : l10n.securitiesHoldingFlat;

    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _onTap(context),
          child: Container(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.10)
              : null,
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.s16,
              vertical: Spacing.s12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OptionalHero(
                        tag: 'asset-${asset.id}-name',
                        enabled: heroEnabled,
                        child: Text(
                          asset.name == null || asset.name!.isEmpty
                              ? asset.symbol
                              : '${asset.symbol} · ${asset.name}',
                          style: theme.textTheme.bodyLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: Spacing.s4),
                      Text(
                        qtyLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: hasQty
                              ? TypographyTokens.tabularFigures
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.s12),
                if (displayValue != null)
                  OptionalHero(
                    tag: 'asset-${asset.id}-value',
                    enabled: heroEnabled,
                    child: MoneyText(
                      amount: displayValue.toDouble(),
                      currencyCode: asset.currency,
                      style: TypographyTokens.numericBody,
                    ),
                  ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (MasterDetailLayout.shouldUseMasterDetail(width)) {
      replaceSelectedQuery(context, path: '/portfolio', selected: asset.id);
    } else {
      context.go('/portfolio/${asset.id}');
    }
  }
}

class _PhysicalAssetsSection extends StatelessWidget {
  const _PhysicalAssetsSection({
    required this.assets,
    required this.selectedAssetId,
  });

  final List<PhysicalAsset> assets;
  final String? selectedAssetId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: Spacing.s8,
            bottom: Spacing.s8,
          ),
          child: Text(
            l10n.physicalAssetsSectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final asset in assets) ...[
          PhysicalAssetCard(asset: asset),
          const SizedBox(height: Spacing.s8),
        ],
        const SizedBox(height: Spacing.s12),
      ],
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.selected,
    required this.heroEnabled,
    this.value,
  });

  final Asset asset;
  final bool selected;
  final bool heroEnabled;
  final Decimal? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final chips = _chipsFor(asset, l10n);
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _onTap(context),
          child: Container(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.10)
              : null,
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.s16,
              vertical: Spacing.s12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OptionalHero(
                        tag: 'asset-${asset.id}-name',
                        enabled: heroEnabled,
                        child: Text(
                          asset.name ?? asset.symbol,
                          style: theme.textTheme.bodyLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: Spacing.s6),
                        Wrap(
                          spacing: Spacing.s6,
                          runSpacing: Spacing.s4,
                          children: chips,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.s12),
                if (value != null)
                  MoneyText(
                    amount: value!.toDouble(),
                    currencyCode: asset.currency,
                    style: TypographyTokens.numericBody,
                  ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (MasterDetailLayout.shouldUseMasterDetail(width)) {
      replaceSelectedQuery(context, path: '/portfolio', selected: asset.id);
    } else {
      context.go('/portfolio/${asset.id}');
    }
  }

  List<Widget> _chipsFor(Asset asset, AppLocalizations l10n) {
    final chips = <Widget>[];
    if (asset.symbol.isNotEmpty &&
        asset.symbol != asset.name &&
        asset.type != AssetType.cash) {
      chips.add(_MetaChip(label: asset.symbol));
    }
    final meta = asset.manualMetadata;
    if (meta is DepositMetadata) {
      chips.add(
        _MetaChip(
          label: l10n.assetsChipInterestRate(
            _formatRatePercent(meta.interestRate),
          ),
        ),
      );
      if (meta.maturityDate != null) {
        final d = meta.maturityDate!;
        chips.add(
          _MetaChip(
            label: l10n.assetsChipMaturityDate(
              '${d.year}-${_two(d.month)}-${_two(d.day)}',
            ),
          ),
        );
      }
    } else if (meta is WealthProductMetadata) {
      chips.add(
        _MetaChip(
          label: l10n.assetsChipExpectedReturn(
            _formatRatePercent(meta.expectedAnnualReturn),
          ),
        ),
      );
      if (meta.issuer != null && meta.issuer!.isNotEmpty) {
        chips.add(_MetaChip(label: meta.issuer!));
      }
    }
    chips.add(_MetaChip(label: asset.currency));
    return chips;
  }

  static String _formatRatePercent(Decimal rate) {
    final pct = (rate * Decimal.fromInt(100)).toDouble();
    return pct
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNumeric = RegExp(r'\d').hasMatch(label);
    final base = theme.textTheme.labelSmall ?? TypographyTokens.labelSmall;
    final textStyle = base.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: isNumeric ? TypographyTokens.tabularFigures : null,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: Radii.brSm,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.s8,
          vertical: Spacing.s2,
        ),
        child: Text(label, style: textStyle),
      ),
    );
  }
}

String manualAssetTypeLabel(AppLocalizations l10n, AssetType t) {
  return switch (t) {
    AssetType.cash => l10n.assetTypeCash,
    AssetType.bankDepositTerm => l10n.assetTypeBankDepositTerm,
    AssetType.bankDepositDemand => l10n.assetTypeBankDepositDemand,
    AssetType.wealthProduct => l10n.assetTypeWealthProduct,
    _ => t.name,
  };
}
