import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';

import '../../../app/master_detail_layout.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../home/domain/dashboard_models.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import '../physical/data/physical_asset.dart';
import 'asset_list_row_widgets.dart';
import 'assets_list_models.dart';

class AssetsDetailEmpty extends StatelessWidget {
  const AssetsDetailEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.assetsAppBarTitle,
      showBack: false,
      childPad: false,
      child: MasterDetailEmpty(
        icon: FLucideIcons.wallet,
        message: l10n.assetsDetailEmpty,
      ),
    );
  }
}

class AssetsBody extends StatelessWidget {
  const AssetsBody({
    super.key,
    required this.manualAsync,
    required this.physicalAsync,
    required this.securitiesAsync,
    required this.holdingsAsync,
    required this.valuationsAsync,
    required this.accountsAsync,
    required this.onRetry,
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
  final AsyncValue<Map<String, HoldingSnapshot>> holdingsAsync;
  final AsyncValue<List<ManualAssetValuation>> valuationsAsync;
  final AsyncValue<List<Account>> accountsAsync;
  final VoidCallback onRetry;
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
        securitiesAsync.isLoading ||
        holdingsAsync.isLoading ||
        valuationsAsync.isLoading ||
        accountsAsync.isLoading;
    return PageSkeletonShell<void>(
      skeleton: const AssetsListSkeleton(),
      isLoading: loading,
      child: _resolveBody(context),
    );
  }

  Widget _resolveBody(BuildContext context) {
    if (manualAsync.isLoading ||
        physicalAsync.isLoading ||
        securitiesAsync.isLoading ||
        holdingsAsync.isLoading ||
        valuationsAsync.isLoading ||
        accountsAsync.isLoading) {
      return const AssetsListSkeleton();
    }
    final loadError =
        _firstError(manualAsync) ??
        _firstError(physicalAsync) ??
        _firstError(securitiesAsync) ??
        _firstError(holdingsAsync) ??
        _firstError(valuationsAsync) ??
        _firstError(accountsAsync);
    if (loadError != null) {
      final l10n = AppLocalizations.of(context);
      return AppEmptyState.error(
        title: l10n.commonLoadFailed,
        message: l10n.assetsLoadError('$loadError'),
        action: FButton(
          variant: FButtonVariant.ghost,
          onPress: onRetry,
          child: Text(l10n.commonRetry),
        ),
      );
    }
    final manual = manualAsync.value ?? const <Asset>[];
    final physical = physicalAsync.value ?? const <PhysicalAsset>[];
    if (manual.isEmpty && physical.isEmpty && securities.isEmpty) {
      return const _EmptyHint();
    }
    final rows = buildAssetRows(
      manual: manual,
      securities: securities,
      physical: physical,
      holdings: holdings,
      valuationMap: valuationMap,
      accountById: accountById,
    );
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.s16).copyWith(
        bottom:
            const EdgeInsets.all(AppSpacing.s16).bottom +
            64 +
            MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: rows.length,
      itemBuilder: (context, i) => AssetListRowWidget(
        row: rows[i],
        selectedAssetId: selectedAssetId,
        inMasterDetail: inMasterDetail,
      ),
    );
  }

  Object? _firstError(AsyncValue<Object?> value) {
    return value.hasError ? value.error : null;
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.wallet,
      title: l10n.assetsEmptyHint,
    );
  }
}
