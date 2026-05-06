import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/master_detail_layout.dart';
import '../../../app/route_paths.dart';
import '../../../app/selection_query.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/manual_asset_metadata.dart';
import '../../../data/repositories/manual_asset_repository.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import '../physical/ui/physical_asset_card.dart';
import 'assets_list_models.dart';

class AssetListRowWidget extends StatelessWidget {
  const AssetListRowWidget({
    super.key,
    required this.row,
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final AssetListRow row;
  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (row) {
      ManualTypeHeaderRow(:final type) => _SectionHeader(
        title: manualAssetTypeLabel(l10n, type),
      ),
      SecurityTypeHeaderRow(:final type) => _SectionHeader(
        title: securitiesAssetTypeLabel(l10n, type),
      ),
      PhysicalHeaderRow() => _SectionHeader(
        title: l10n.physicalAssetsSectionTitle,
      ),
      CashGroupHeaderRow(:final accountId, :final account) =>
        _AccountGroupHeader(accountId: accountId, account: account),
      ManualAssetTileRow(:final asset, :final value) => _TertiaryRowSurface(
        child: _AssetTile(
          asset: asset,
          selected: asset.id == selectedAssetId,
          heroEnabled: !inMasterDetail,
          value: value,
        ),
      ),
      SecurityAssetTileRow(:final asset, :final snapshot) =>
        _TertiaryRowSurface(
          child: _SecurityTile(
            asset: asset,
            snapshot: snapshot,
            selected: asset.id == selectedAssetId,
            heroEnabled: !inMasterDetail,
          ),
        ),
      PhysicalAssetTileRow(:final asset) => PhysicalAssetCard(asset: asset),
      GapRow(:final height) => SizedBox(height: height),
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
    final displayValue = snapshot?.marketValueInAssetCurrency;
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

String manualAssetTypeLabel(AppLocalizations l10n, AssetType t) {
  return switch (t) {
    AssetType.cash => l10n.assetTypeCash,
    AssetType.bankDepositTerm => l10n.assetTypeBankDepositTerm,
    AssetType.bankDepositDemand => l10n.assetTypeBankDepositDemand,
    AssetType.wealthProduct => l10n.assetTypeWealthProduct,
    _ => t.name,
  };
}
