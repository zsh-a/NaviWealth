import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../data/domain/enums.dart';
import '../features/assets/physical/ui/physical_asset_create_sheet.dart';
import '../l10n/gen/app_localizations.dart';
import 'route_paths.dart';

Future<void> showGlobalActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ListView(
      shrinkWrap: true,
      children: [
        FTile(
          title: Text(l10n.superFabExpense),
          prefix: const Icon(Icons.add_card_outlined),
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.expenseNew),
        ),
        FTile(
          title: Text(l10n.superFabTrade),
          prefix: const Icon(Icons.add_chart_outlined),
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.tradeEntry),
        ),
        FTile(
          title: Text(l10n.superFabAsset),
          prefix: const Icon(Icons.account_balance_wallet_outlined),
          onPress: () {
            Navigator.of(sheetContext).pop();
            showAssetActionPanel(context);
          },
        ),
        FTile(
          title: Text(l10n.superFabTransfer),
          prefix: const Icon(Icons.swap_horiz),
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountTransfer),
        ),
        FTile(
          title: Text(l10n.accountFormCreateTitle),
          prefix: const Icon(Icons.add_card_outlined),
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountNew),
        ),
        FTile(
          title: Text(l10n.superFabLiability),
          prefix: const Icon(Icons.payments_outlined),
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.liabilityNew),
        ),
      ],
    ),
  );
}

Future<void> showAssetActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ListView(
      shrinkWrap: true,
      children: [
        _sectionHeader(theme, l10n.portfolioAssetsTab),
        FTile(
          title: Text(l10n.assetsAddCashTitle),
          prefix: const Icon(Icons.account_balance_wallet_outlined),
          subtitle: Text(l10n.assetsAddCashSubtitle),
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.portfolioNewCash),
        ),
        FTile(
          title: Text(l10n.assetsAddDepositTitle),
          prefix: const Icon(Icons.savings_outlined),
          subtitle: Text(l10n.assetsAddDepositSubtitle),
          onPress: () => _closeAndPush(
            sheetContext,
            context,
            AppRoutes.portfolioNewDeposit,
          ),
        ),
        FTile(
          title: Text(l10n.assetsAddWealthTitle),
          prefix: const Icon(Icons.auto_graph_outlined),
          subtitle: Text(l10n.assetsAddWealthSubtitle),
          onPress: () => _closeAndPush(
            sheetContext,
            context,
            AppRoutes.portfolioNewWealth,
          ),
        ),
        FTile(
          title: Text(l10n.physicalAssetAddRealEstate),
          prefix: const Icon(Icons.home_outlined),
          subtitle: Text(l10n.assetsAddRealEstateSubtitle),
          onPress: () => _closeAndOpenPhysical(
            sheetContext,
            context,
            AssetType.realEstate,
          ),
        ),
        FTile(
          title: Text(l10n.physicalAssetAddVehicle),
          prefix: const Icon(Icons.directions_car_outlined),
          subtitle: Text(l10n.assetsAddVehicleSubtitle),
          onPress: () =>
              _closeAndOpenPhysical(sheetContext, context, AssetType.vehicle),
        ),
      ],
    ),
  );
}

Widget _sectionHeader(ThemeData theme, String title) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

void _closeAndPush(
  BuildContext sheetContext,
  BuildContext routeContext,
  String path,
) {
  Navigator.of(sheetContext).pop();
  routeContext.push(path);
}

Future<void> _closeAndOpenPhysical(
  BuildContext sheetContext,
  BuildContext routeContext,
  AssetType type,
) async {
  Navigator.of(sheetContext).pop();
  final created = await PhysicalAssetCreateSheet.show(routeContext, type: type);
  if (created != null && routeContext.mounted) {
    routeContext.goNamed(
      AppRouteNames.physicalAssetDetail,
      pathParameters: {'id': created.id},
    );
  }
}
