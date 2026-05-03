import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/master_detail_layout.dart';
import '../../app/selection_query.dart';
import '../../core/shortcuts/master_detail_shortcuts.dart';
import '../../data/domain/asset.dart';
import '../../data/domain/enums.dart';
import '../../data/domain/manual_asset_metadata.dart';
import '../../data/repositories/manual_asset_repository.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../ai_chat/ui/ai_chat_sheet.dart';
import '../investment/data/providers.dart';
import '../investment/domain/models/holding_snapshot.dart';
import 'asset_detail_page.dart';
import 'physical/data/physical_asset.dart';
import 'physical/data/providers.dart';
import 'physical/ui/physical_asset_card.dart';
import 'physical/ui/physical_asset_create_sheet.dart';

/// Tab body for `/assets`. Shows the manual-valuation asset book
/// (cash, deposits, wealth products) grouped by type, plus a "real estate
/// & vehicles" section for non-financial assets, and a FAB that opens a
/// bottom sheet to choose which kind of asset to add.
///
/// At desktop width (≥ 1240) the page renders as a master-detail surface
/// (FIR-106): a 380dp asset list on the left and the asset detail page
/// on the right, driven by the `?selected=` query parameter. Tapping a
/// row at narrower widths still pushes the detail route in the usual
/// way.
class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key, this.embedded = false});

  /// When true, renders without Scaffold/AppBar/FAB — for embedding
  /// inside [PortfolioPage].
  final bool embedded;

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
          if (embedded) {
            return MasterDetailLayout(
              master: _AssetsMaster(
                selectedAssetId: selected,
                inMasterDetail: true,
                embedded: true,
              ),
              detail: detail,
            );
          }
          return Scaffold(
            body: MasterDetailLayout(
              master: _AssetsMaster(
                selectedAssetId: selected,
                inMasterDetail: true,
                embedded: false,
              ),
              detail: detail,
            ),
          );
        }
        return _AssetsMaster(
          selectedAssetId: null,
          inMasterDetail: false,
          embedded: embedded,
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
    this.embedded = false,
  });

  final String? selectedAssetId;
  final bool inMasterDetail;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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

    if (embedded) {
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

    return MasterDetailShortcuts(
      onSelectNext: allIds.isEmpty
          ? null
          : () => _selectAdjacent(context, allIds, delta: 1),
      onSelectPrevious: allIds.isEmpty
          ? null
          : () => _selectAdjacent(context, allIds, delta: -1),
      child: Scaffold(
        appBar: GlassAppBar(
          title: Text(l10n.assetsAppBarTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: l10n.homeAiAssistantTooltip,
              onPressed: () => showAiChatSheet(context),
            ),
            IconButton(
              icon: const Icon(Icons.account_balance_outlined),
              tooltip: l10n.assetsAccountsTooltip,
              onPressed: () => context.go('/accounts'),
            ),
            IconButton(
              icon: const Icon(Icons.payments_outlined),
              tooltip: l10n.assetsLiabilitiesTooltip,
              onPressed: () => context.push('/portfolio/liabilities'),
            ),
          ],
        ),
        body: body,
        floatingActionButton: ScrollAwareFab(
          child: AppFab.extended(
            onPressed: () => _showAddSheet(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.assetsAddAction),
          ),
        ),
      ),
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

  void _showAddSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showGlassModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(l10n.assetsAddCashTitle),
              subtitle: Text(l10n.assetsAddCashSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/portfolio/new/cash');
              },
            ),
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: Text(l10n.assetsAddDepositTitle),
              subtitle: Text(l10n.assetsAddDepositSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/portfolio/new/deposit');
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_graph_outlined),
              title: Text(l10n.assetsAddWealthTitle),
              subtitle: Text(l10n.assetsAddWealthSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/portfolio/new/wealth');
              },
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(l10n.physicalAssetAddRealEstate),
              subtitle: Text(l10n.assetsAddRealEstateSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                _openPhysicalCreate(context, AssetType.realEstate);
              },
            ),
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: Text(l10n.physicalAssetAddVehicle),
              subtitle: Text(l10n.assetsAddVehicleSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                _openPhysicalCreate(context, AssetType.vehicle);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(l10n.assetsAddLiabilityTitle),
              subtitle: Text(l10n.assetsAddLiabilitySubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/portfolio/liabilities');
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(l10n.assetsCorporateActionAction),
              subtitle: Text(l10n.assetsAddCorporateActionSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/portfolio/corporate-action');
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_outlined),
              title: Text(l10n.assetsAddTradeTitle),
              subtitle: Text(l10n.assetsAddTradeSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/portfolio/trade');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPhysicalCreate(
    BuildContext context,
    AssetType type,
  ) async {
    final created = await PhysicalAssetCreateSheet.show(context, type: type);
    if (created != null && context.mounted) {
      context.goNamed(
        'physicalAssetDetail',
        pathParameters: {'id': created.id},
      );
    }
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
    return ListView(
      padding: Spacing.pageMobile,
      children: [
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
      ],
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

class _ManualAssetsSection extends StatelessWidget {
  const _ManualAssetsSection({
    required this.assets,
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final List<Asset> assets;
  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final asset in grouped[type]!)
                  _AssetTile(
                    asset: asset,
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
          Card(
            clipBehavior: Clip.antiAlias,
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
  });

  final Asset asset;
  final bool selected;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final chips = _chipsFor(asset, l10n);
    return MergeSemantics(
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
              ],
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
