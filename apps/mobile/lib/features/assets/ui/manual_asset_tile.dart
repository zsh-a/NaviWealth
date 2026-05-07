import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/master_detail_layout.dart';
import '../../../app/route_paths.dart';
import '../../../app/selection_query.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/manual_asset_metadata.dart';
import '../../../data/repositories/manual_asset_repository.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

class ManualAssetTile extends StatelessWidget {
  const ManualAssetTile({
    super.key,
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
