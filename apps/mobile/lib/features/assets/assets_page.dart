import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/master_detail_layout.dart';
import '../../app/route_paths.dart';
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
    final valuationsAsync = ref.watch(dashboardManualAssetValuationsProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);

    final securitiesOrdered = _orderedSecurities(securitiesAsync.value);
    final valuationMap = <String, Decimal>{};
    for (final v in valuationsAsync.value ?? const <ManualAssetValuation>[]) {
      final value = v.currentValue();
      // Cash can go negative (trade overdraw); always include it.
      // Other manual assets with non-positive values are excluded.
      if (value != null && (value.sign > 0 || v.asset.type == AssetType.cash)) {
        valuationMap[v.asset.id] = value;
      }
    }
    final accounts = accountsAsync.value ?? const <Account>[];
    final accountById = {for (final a in accounts) a.id: a};

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
      valuationMap: valuationMap,
      accountById: accountById,
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
    replaceSelectedQuery(
      context,
      path: AppRoutes.portfolio,
      selected: allIds[nextIndex],
    );
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
    required this.valuationMap,
    required this.accountById,
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final AsyncValue<List<Asset>> manualAsync;
  final AsyncValue<List<PhysicalAsset>> physicalAsync;
  final AsyncValue<List<Asset>> securitiesAsync;
  final List<Asset> securities;
  final Map<String, HoldingSnapshot> holdings;
  final Map<String, Decimal> valuationMap;
  final Map<String, Account> accountById;
  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context) {
    final loading =
        manualAsync.isLoading ||
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
    final securitiesErr = securitiesAsync.hasError
        ? securitiesAsync.error
        : null;
    if (manualErr != null && physicalErr != null && securitiesErr != null) {
      return Center(
        child: Text(AppLocalizations.of(context).assetsLoadError('$manualErr')),
      );
    }
    final manual = manualAsync.value ?? const <Asset>[];
    final physical = physicalAsync.value ?? const <PhysicalAsset>[];
    if (manual.isEmpty && physical.isEmpty && securities.isEmpty) {
      return const _EmptyHint();
    }
    final rows = _buildAssetRows(
      manual: manual,
      securities: securities,
      physical: physical,
      holdings: holdings,
      valuationMap: valuationMap,
      accountById: accountById,
    );
    return ScrollNotificationHandler(
      child: ListView.builder(
        padding: Spacing.pageMobile.copyWith(
          bottom:
              Spacing.pageMobile.bottom +
              Spacing.floatingBarClearance +
              MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: rows.length,
        itemBuilder: (context, i) => _AssetListRowWidget(
          row: rows[i],
          selectedAssetId: selectedAssetId,
          inMasterDetail: inMasterDetail,
        ),
      ),
    );
  }
}

List<_AssetListRow> _buildAssetRows({
  required List<Asset> manual,
  required List<Asset> securities,
  required List<PhysicalAsset> physical,
  required Map<String, HoldingSnapshot> holdings,
  required Map<String, Decimal> valuationMap,
  required Map<String, Account> accountById,
}) {
  final rows = <_AssetListRow>[];

  final manualGrouped = <AssetType, List<Asset>>{};
  for (final a in manual) {
    manualGrouped.putIfAbsent(a.type, () => []).add(a);
  }
  final manualOrder = [
    AssetType.cash,
    AssetType.bankDepositDemand,
    AssetType.bankDepositTerm,
    AssetType.wealthProduct,
  ].where(manualGrouped.containsKey);

  for (final type in manualOrder) {
    rows.add(_ManualTypeHeaderRow(type));
    if (type == AssetType.cash) {
      rows.addAll(
        _cashRows(
          manualGrouped[type]!,
          valuationMap: valuationMap,
          accountById: accountById,
        ),
      );
    } else {
      for (final asset in manualGrouped[type]!) {
        rows.add(_ManualAssetTileRow(asset, valuationMap[asset.id]));
      }
    }
    rows.add(const _GapRow(Spacing.s12));
  }

  final securitiesGrouped = <AssetType, List<Asset>>{};
  for (final a in securities) {
    securitiesGrouped.putIfAbsent(a.type, () => []).add(a);
  }
  final securitiesOrder = _kSecuritiesTypeOrder
      .where(securitiesGrouped.containsKey)
      .toList(growable: false);
  for (final type in securitiesOrder) {
    rows.add(_SecurityTypeHeaderRow(type));
    for (final asset in securitiesGrouped[type]!) {
      rows.add(_SecurityAssetTileRow(asset, holdings[asset.id]));
    }
    rows.add(const _GapRow(Spacing.s12));
  }

  if (physical.isNotEmpty) {
    rows.add(const _PhysicalHeaderRow());
    for (final asset in physical) {
      rows.add(_PhysicalAssetTileRow(asset));
      rows.add(const _GapRow(Spacing.s8));
    }
    rows.add(const _GapRow(Spacing.s12));
  }

  return rows;
}

List<_AssetListRow> _cashRows(
  List<Asset> cashAssets, {
  required Map<String, Decimal> valuationMap,
  required Map<String, Account> accountById,
}) {
  final rows = <_AssetListRow>[];
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

  final sortedAccountIds = byAccount.keys.toList()
    ..sort((a, b) {
      final aa = accountById[a];
      final bb = accountById[b];
      if (aa == null && bb == null) return 0;
      if (aa == null) return 1;
      if (bb == null) return -1;
      return aa.name.compareTo(bb.name);
    });

  for (final accountId in sortedAccountIds) {
    rows.add(_CashGroupHeaderRow(accountId, accountById[accountId]));
    for (final asset in byAccount[accountId]!) {
      rows.add(_ManualAssetTileRow(asset, valuationMap[asset.id]));
    }
  }
  for (final asset in orphanAssets) {
    rows.add(_ManualAssetTileRow(asset, valuationMap[asset.id]));
  }
  return rows;
}

sealed class _AssetListRow {
  const _AssetListRow();
}

class _ManualTypeHeaderRow extends _AssetListRow {
  const _ManualTypeHeaderRow(this.type);
  final AssetType type;
}

class _SecurityTypeHeaderRow extends _AssetListRow {
  const _SecurityTypeHeaderRow(this.type);
  final AssetType type;
}

class _PhysicalHeaderRow extends _AssetListRow {
  const _PhysicalHeaderRow();
}

class _CashGroupHeaderRow extends _AssetListRow {
  const _CashGroupHeaderRow(this.accountId, this.account);
  final String accountId;
  final Account? account;
}

class _ManualAssetTileRow extends _AssetListRow {
  const _ManualAssetTileRow(this.asset, this.value);
  final Asset asset;
  final Decimal? value;
}

class _SecurityAssetTileRow extends _AssetListRow {
  const _SecurityAssetTileRow(this.asset, this.snapshot);
  final Asset asset;
  final HoldingSnapshot? snapshot;
}

class _PhysicalAssetTileRow extends _AssetListRow {
  const _PhysicalAssetTileRow(this.asset);
  final PhysicalAsset asset;
}

class _GapRow extends _AssetListRow {
  const _GapRow(this.height);
  final double height;
}

class _AssetListRowWidget extends StatelessWidget {
  const _AssetListRowWidget({
    required this.row,
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final _AssetListRow row;
  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (row) {
      _ManualTypeHeaderRow(:final type) => _SectionHeader(
        title: manualAssetTypeLabel(l10n, type),
      ),
      _SecurityTypeHeaderRow(:final type) => _SectionHeader(
        title: securitiesAssetTypeLabel(l10n, type),
      ),
      _PhysicalHeaderRow() => _SectionHeader(
        title: l10n.physicalAssetsSectionTitle,
      ),
      _CashGroupHeaderRow(:final accountId, :final account) =>
        _AccountGroupHeader(accountId: accountId, account: account),
      _ManualAssetTileRow(:final asset, :final value) => _TertiaryRowSurface(
        child: _AssetTile(
          asset: asset,
          selected: asset.id == selectedAssetId,
          heroEnabled: !inMasterDetail,
          value: value,
        ),
      ),
      _SecurityAssetTileRow(:final asset, :final snapshot) =>
        _TertiaryRowSurface(
          child: _SecurityTile(
            asset: asset,
            snapshot: snapshot,
            selected: asset.id == selectedAssetId,
            heroEnabled: !inMasterDetail,
          ),
        ),
      _PhysicalAssetTileRow(:final asset) => PhysicalAssetCard(asset: asset),
      _GapRow(:final height) => SizedBox(height: height),
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.s8, bottom: Spacing.s8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _TertiaryRowSurface extends StatelessWidget {
  const _TertiaryRowSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCard(
      layer: GlassLayer.tertiary,
      padding: EdgeInsets.zero,
      child: child,
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
            Text(l10n.assetsEmptyHint, textAlign: TextAlign.center),
          ],
        ),
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
      replaceSelectedQuery(
        context,
        path: AppRoutes.portfolio,
        selected: asset.id,
      );
    } else {
      context.go(AppRoutes.portfolioAsset(asset.id));
    }
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
      replaceSelectedQuery(
        context,
        path: AppRoutes.portfolio,
        selected: asset.id,
      );
    } else {
      context.go(AppRoutes.portfolioAsset(asset.id));
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
