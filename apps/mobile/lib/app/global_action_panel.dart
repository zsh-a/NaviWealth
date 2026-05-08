import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/domain/enums.dart';
import '../design_system/design_system.dart';
import '../features/assets/physical/ui/physical_asset_create_sheet.dart';
import '../l10n/gen/app_localizations.dart';
import 'route_paths.dart';

Future<void> showGlobalActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showGlassModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          leading: const Icon(Icons.add_card_outlined),
          title: Text(l10n.superFabExpense),
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.expenseNew),
        ),
        ListTile(
          leading: const Icon(Icons.add_chart_outlined),
          title: Text(l10n.superFabTrade),
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.tradeEntry),
        ),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(l10n.superFabAsset),
          onTap: () {
            Navigator.of(sheetContext).pop();
            showAssetActionPanel(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: Text(l10n.superFabTransfer),
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountTransfer),
        ),
        ListTile(
          leading: const Icon(Icons.add_card_outlined),
          title: Text(l10n.accountFormCreateTitle),
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountNew),
        ),
        ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: Text(l10n.superFabLiability),
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.liabilityNew),
        ),
      ],
    ),
  );
}

Future<void> showAssetActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  return showGlassModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ListView(
      shrinkWrap: true,
      children: [
        _sectionHeader(theme, l10n.portfolioAssetsTab),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(l10n.assetsAddCashTitle),
          subtitle: Text(l10n.assetsAddCashSubtitle),
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.portfolioNewCash),
        ),
        ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: Text(l10n.assetsAddDepositTitle),
          subtitle: Text(l10n.assetsAddDepositSubtitle),
          onTap: () => _closeAndPush(
            sheetContext,
            context,
            AppRoutes.portfolioNewDeposit,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.auto_graph_outlined),
          title: Text(l10n.assetsAddWealthTitle),
          subtitle: Text(l10n.assetsAddWealthSubtitle),
          onTap: () => _closeAndPush(
            sheetContext,
            context,
            AppRoutes.portfolioNewWealth,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.home_outlined),
          title: Text(l10n.physicalAssetAddRealEstate),
          subtitle: Text(l10n.assetsAddRealEstateSubtitle),
          onTap: () => _closeAndOpenPhysical(
            sheetContext,
            context,
            AssetType.realEstate,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.directions_car_outlined),
          title: Text(l10n.physicalAssetAddVehicle),
          subtitle: Text(l10n.assetsAddVehicleSubtitle),
          onTap: () =>
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
