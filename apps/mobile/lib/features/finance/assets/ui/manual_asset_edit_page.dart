import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'cash_form_page.dart';
import 'deposit_form_page.dart';
import 'wealth_product_form_page.dart';

class ManualAssetEditRoute extends ConsumerWidget {
  const ManualAssetEditRoute({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repoAsync = ref.watch(manualAssetRepositoryProvider);
    return repoAsync.when(
      loading: () => AppPageScaffold(
        title: l10n.assetDetailUnknown,
        child: const AssetDetailSkeleton(),
      ),
      error: (error, stackTrace) => AppPageScaffold(
        title: l10n.assetDetailUnknown,
        child: AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, error, stackTrace: stackTrace),
        ),
      ),
      data: (repo) => FutureBuilder<Asset?>(
        future: repo.findById(assetId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AppPageScaffold(
              title: l10n.assetDetailUnknown,
              child: const AssetDetailSkeleton(),
            );
          }
          final asset = snapshot.data;
          if (asset == null) {
            return AppPageScaffold(
              title: l10n.assetDetailUnknown,
              child: Center(child: Text(l10n.assetDetailNotFound)),
            );
          }
          return ManualAssetEditPage(asset: asset);
        },
      ),
    );
  }
}

class ManualAssetEditPage extends StatelessWidget {
  const ManualAssetEditPage({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    return switch (asset.type) {
      AssetType.cash => CashFormPage(assetId: asset.id),
      AssetType.bankDepositTerm ||
      AssetType.bankDepositDemand => DepositFormPage(assetId: asset.id),
      AssetType.wealthProduct => WealthProductFormPage(assetId: asset.id),
      _ => AppPageScaffold(
        title: asset.name ?? asset.symbol,
        child: Center(
          child: Text(AppLocalizations.of(context).assetDetailUnsupportedType),
        ),
      ),
    };
  }
}
