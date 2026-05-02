import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/domain/asset.dart';
import '../../data/domain/enums.dart';
import '../../data/domain/manual_asset_metadata.dart';
import '../../data/repositories/manual_asset_repository.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'physical/data/physical_asset.dart';
import 'physical/data/providers.dart';
import 'physical/ui/physical_asset_card.dart';
import 'physical/ui/physical_asset_create_sheet.dart';

/// Tab body for `/assets`. Shows the manual-valuation asset book
/// (cash, deposits, wealth products) grouped by type, plus a "real estate
/// & vehicles" section for non-financial assets, and a FAB that opens a
/// bottom sheet to choose which kind of asset to add.
///
/// Securities / crypto holdings will be appended once their feature ticket
/// lands; this page intentionally only knows about manually-valued rows so
/// the two surfaces can evolve independently.
class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final manualAsync = ref.watch(manualAssetsStreamProvider);
    final physicalAsync = ref.watch(physicalAssetsListProvider);
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.assetsAppBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_outlined),
            tooltip: l10n.assetsAccountsTooltip,
            onPressed: () => context.go('/accounts'),
          ),
          IconButton(
            icon: const Icon(Icons.payments_outlined),
            tooltip: l10n.assetsLiabilitiesTooltip,
            onPressed: () => context.push('/assets/liabilities'),
          ),
        ],
      ),
      body: _AssetsBody(
        manualAsync: manualAsync,
        physicalAsync: physicalAsync,
      ),
      floatingActionButton: AppFab.extended(
        onPressed: () => _showAddSheet(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.assetsAddAction),
      ),
    );
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
                context.go('/assets/new/cash');
              },
            ),
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: Text(l10n.assetsAddDepositTitle),
              subtitle: Text(l10n.assetsAddDepositSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/assets/new/deposit');
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_graph_outlined),
              title: Text(l10n.assetsAddWealthTitle),
              subtitle: Text(l10n.assetsAddWealthSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/assets/new/wealth');
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
                context.push('/assets/liabilities');
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(l10n.assetsCorporateActionAction),
              subtitle: Text(l10n.assetsAddCorporateActionSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/assets/corporate-action');
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_outlined),
              title: Text(l10n.assetsAddTradeTitle),
              subtitle: Text(l10n.assetsAddTradeSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/assets/trade');
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

class _AssetsBody extends StatelessWidget {
  const _AssetsBody({
    required this.manualAsync,
    required this.physicalAsync,
  });

  final AsyncValue<List<Asset>> manualAsync;
  final AsyncValue<List<PhysicalAsset>> physicalAsync;

  @override
  Widget build(BuildContext context) {
    final loading = manualAsync.isLoading || physicalAsync.isLoading;
    return PageSkeletonShell<void>(
      skeleton: const AssetsListSkeleton(),
      isLoading: loading,
      child: _resolveBody(context),
    );
  }

  Widget _resolveBody(BuildContext context) {
    if (manualAsync.isLoading || physicalAsync.isLoading) {
      return const AssetsListSkeleton();
    }
    final manualErr = manualAsync.hasError ? manualAsync.error : null;
    final physicalErr = physicalAsync.hasError ? physicalAsync.error : null;
    if (manualErr != null && physicalErr != null) {
      return Center(
        child: Text(
          AppLocalizations.of(context).assetsLoadError('$manualErr'),
        ),
      );
    }
    final manual = manualAsync.value ?? const <Asset>[];
    final physical = physicalAsync.value ?? const <PhysicalAsset>[];
    if (manual.isEmpty && physical.isEmpty) {
      return const _EmptyHint();
    }
    return ListView(
      padding: Spacing.pageMobile,
      children: [
        if (manual.isNotEmpty) _ManualAssetsSection(assets: manual),
        if (physical.isNotEmpty) _PhysicalAssetsSection(assets: physical),
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
  const _ManualAssetsSection({required this.assets});

  final List<Asset> assets;

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
                for (final asset in grouped[type]!) _AssetTile(asset: asset),
              ],
            ),
          ),
          const SizedBox(height: Spacing.s12),
        ],
      ],
    );
  }
}

class _PhysicalAssetsSection extends StatelessWidget {
  const _PhysicalAssetsSection({required this.assets});

  final List<PhysicalAsset> assets;

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
  const _AssetTile({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final price = asset.lastPrice ?? Decimal.zero;
    final chips = _chipsFor(asset, l10n);
    return MergeSemantics(
      child: InkWell(
        onTap: () => context.go('/assets/${asset.id}'),
        child: ConstrainedBox(
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
                      Text(
                        asset.name ?? asset.symbol,
                        style: theme.textTheme.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                MoneyText(
                  amount: price.toDouble(),
                  currencyCode: asset.currency,
                  style: TypographyTokens.numericBody,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
