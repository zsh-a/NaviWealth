import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/domain/asset.dart';
import '../../data/domain/enums.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'cash_form_page.dart';
import 'deposit_form_page.dart';
import 'ui/equity_asset_detail_page.dart';
import 'wealth_product_form_page.dart';

/// Resolves an asset id to the type-specific edit form.
///
/// Centralising the dispatch keeps the route table flat — the router
/// doesn't need to know which sub-form belongs to which AssetType, and
/// adding new manual-valuation flavours later means changing only this
/// switch.
class AssetDetailPage extends ConsumerWidget {
  const AssetDetailPage({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repoAsync = ref.watch(manualAssetRepositoryProvider);
    return repoAsync.when(
      loading: () => const FScaffold(
        childPad: false,
        child: Material(
          color: Colors.transparent,
          child: AssetDetailSkeleton(),
        ),
      ),
      error: (e, _) => FScaffold(
        childPad: false,
        child: Material(
          color: Colors.transparent,
          child: Center(child: Text(l10n.assetDetailLoadError('$e'))),
        ),
      ),
      data: (repo) {
        return FutureBuilder<Asset?>(
          future: repo.findById(assetId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const FScaffold(
                childPad: false,
                child: Material(
                  color: Colors.transparent,
                  child: AssetDetailSkeleton(),
                ),
              );
            }
            final asset = snap.data;
            if (asset == null) {
              return FScaffold(
                childPad: false,
                child: Material(
                  color: Colors.transparent,
                  child: Center(child: Text(l10n.assetDetailNotFound)),
                ),
              );
            }
            return switch (asset.type) {
              AssetType.cash => CashFormPage(assetId: asset.id),
              AssetType.bankDepositTerm ||
              AssetType.bankDepositDemand => DepositFormPage(assetId: asset.id),
              AssetType.wealthProduct => WealthProductFormPage(
                assetId: asset.id,
              ),
              AssetType.stock ||
              AssetType.etf ||
              AssetType.crypto ||
              AssetType.mutualFund => EquityAssetDetailPage(assetId: asset.id),
              _ => FScaffold(
                header: FHeader.nested(title: Text(asset.name ?? asset.symbol)),
                childPad: false,
                child: Material(
                  color: Colors.transparent,
                  child: Center(child: Text(l10n.assetDetailUnsupportedType)),
                ),
              ),
            };
          },
        );
      },
    );
  }
}
