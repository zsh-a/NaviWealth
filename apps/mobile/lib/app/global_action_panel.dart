import 'package:flutter/material.dart' show Icons, Navigator;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../data/domain/enums.dart';
import '../features/assets/physical/ui/physical_asset_create_sheet.dart';
import '../l10n/gen/app_localizations.dart';
import 'route_paths.dart';

Future<void> showGlobalActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showFSheet<void>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
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
            subtitle: Text(l10n.superFabTransferSubtitle),
            onPress: () =>
                _closeAndPush(sheetContext, context, AppRoutes.transfer),
          ),
          FTile(
            title: Text(l10n.superFabConvert),
            prefix: const Icon(Icons.currency_exchange),
            subtitle: Text(l10n.superFabConvertSubtitle),
            onPress: () => _closeAndPush(
              sheetContext,
              context,
              '${AppRoutes.transfer}?convert=1',
            ),
          ),
          FTile(
            title: Text(l10n.accountFormCreateTitle),
            prefix: const Icon(Icons.add_card_outlined),
            onPress: () =>
                _closeAndPush(sheetContext, context, AppRoutes.accountListNew),
          ),
          FTile(
            title: Text(l10n.superFabLiability),
            prefix: const Icon(Icons.payments_outlined),
            onPress: () =>
                _closeAndPush(sheetContext, context, AppRoutes.liabilityNew),
          ),
        ],
      ),
    ),
  );
}

Future<void> showAssetActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showFSheet<void>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _SectionHeader(title: l10n.portfolioAssetsTab),
          FTile(
            title: Text(l10n.assetsAddCashTitle),
            prefix: const Icon(Icons.account_balance_wallet_outlined),
            subtitle: Text(l10n.assetsAddCashSubtitle),
            onPress: () => _closeAndPush(
              sheetContext,
              context,
              AppRoutes.accountNewCash,
            ),
          ),
          FTile(
            title: Text(l10n.assetsAddDepositTitle),
            prefix: const Icon(Icons.savings_outlined),
            subtitle: Text(l10n.assetsAddDepositSubtitle),
            onPress: () => _closeAndPush(
              sheetContext,
              context,
              AppRoutes.accountNewDeposit,
            ),
          ),
          FTile(
            title: Text(l10n.assetsAddWealthTitle),
            prefix: const Icon(Icons.auto_graph_outlined),
            subtitle: Text(l10n.assetsAddWealthSubtitle),
            onPress: () => _closeAndPush(
              sheetContext,
              context,
              AppRoutes.accountNewWealth,
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
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: context.theme.typography.xs.copyWith(
          color: colors.mutedForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
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
