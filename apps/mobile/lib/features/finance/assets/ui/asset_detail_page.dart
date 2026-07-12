import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'equity_asset_detail_page.dart';
import 'manual_asset_detail_page.dart';

/// Resolves an asset id to a read-first type-specific detail surface.
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
      loading: () => AppPageScaffold(
        title: l10n.assetDetailUnknown,
        childPad: false,
        child: const AssetDetailSkeleton(),
      ),
      error: (e, _) => AppPageScaffold(
        title: l10n.assetDetailUnknown,
        childPad: false,
        child: Center(child: Text(userSafeErrorMessage(context, e))),
      ),
      data: (repo) {
        return FutureBuilder<Asset?>(
          future: repo.findById(assetId),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return AppPageScaffold(
                title: l10n.assetDetailUnknown,
                childPad: false,
                child: const AssetDetailSkeleton(),
              );
            }
            if (snap.hasError) {
              return AppPageScaffold(
                title: l10n.assetDetailUnknown,
                childPad: false,
                child: AppEmptyState.error(
                  title: l10n.commonLoadFailed,
                  message: userSafeErrorMessage(
                    context,
                    snap.error!,
                    stackTrace: snap.stackTrace,
                  ),
                  retryLabel: l10n.commonRetry,
                  onRetry: () => ref.invalidate(manualAssetRepositoryProvider),
                ),
              );
            }
            final asset = snap.data;
            if (asset == null) {
              return AppPageScaffold(
                title: l10n.assetDetailUnknown,
                childPad: false,
                child: Center(child: Text(l10n.assetDetailNotFound)),
              );
            }
            return switch (asset.type) {
              AssetType.cash ||
              AssetType.bankDepositTerm ||
              AssetType.bankDepositDemand ||
              AssetType.wealthProduct => ManualAssetDetailPage(
                asset: asset,
                repository: repo,
              ),
              AssetType.stock ||
              AssetType.etf ||
              AssetType.crypto ||
              AssetType.mutualFund => EquityAssetDetailPage(assetId: asset.id),
              _ => AppPageScaffold(
                title: asset.name ?? asset.symbol,
                childPad: false,
                child: Center(child: Text(l10n.assetDetailUnsupportedType)),
              ),
            };
          },
        );
      },
    );
  }
}
