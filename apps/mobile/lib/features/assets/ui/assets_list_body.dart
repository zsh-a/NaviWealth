import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/master_detail_layout.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/asset.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import '../physical/data/physical_asset.dart';
import 'asset_list_row_widgets.dart';
import 'assets_list_models.dart';

class AssetsDetailEmpty extends StatelessWidget {
  const AssetsDetailEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      header: FHeader.nested(title: Text(l10n.assetsAppBarTitle)),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: MasterDetailEmpty(
          icon: Icons.account_balance_wallet_outlined,
          message: l10n.assetsDetailEmpty,
        ),
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
    final rows = buildAssetRows(
      manual: manual,
      securities: securities,
      physical: physical,
      holdings: holdings,
      valuationMap: valuationMap,
      accountById: accountById,
    );
    return ListView.builder(
      padding: Spacing.pageMobile.copyWith(
        bottom:
            Spacing.pageMobile.bottom +
            Spacing.floatingBarClearance +
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
