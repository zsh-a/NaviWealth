import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/data/asset_detail_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
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
    final assetAsync = ref.watch(manualAssetByIdProvider(assetId));
    return repoAsync.when(
      loading: () => AppPageScaffold(
        title: l10n.assetDetailUnknown,
        childPad: false,
        child: const AssetDetailSkeleton(),
      ),
      error: (e, _) => AppPageScaffold(
        title: l10n.assetDetailUnknown,
        childPad: false,
        child: AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, e),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(manualAssetRepositoryProvider),
        ),
      ),
      data: (repo) => assetAsync.when(
        loading: () => AppPageScaffold(
          title: l10n.assetDetailUnknown,
          childPad: false,
          child: const AssetDetailSkeleton(),
        ),
        error: (error, stackTrace) {
          return AppPageScaffold(
            title: l10n.assetDetailUnknown,
            childPad: false,
            child: AppEmptyState.error(
              title: l10n.commonLoadFailed,
              message: userSafeErrorMessage(
                context,
                error,
                stackTrace: stackTrace,
              ),
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(manualAssetByIdProvider(assetId)),
            ),
          );
        },
        data: (asset) {
          if (asset == null) {
            return AppPageScaffold(
              title: l10n.assetDetailUnknown,
              childPad: false,
              child: AppEmptyState(
                icon: FLucideIcons.box,
                title: l10n.assetDetailNotFound,
                action: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => smartPop(context),
                  child: Text(l10n.commonClose),
                ),
              ),
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
              child: AppEmptyState(
                icon: FLucideIcons.circleX,
                title: l10n.assetDetailUnsupportedType,
                action: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => smartPop(context),
                  child: Text(l10n.commonClose),
                ),
              ),
            ),
          };
        },
      ),
    );
  }
}
