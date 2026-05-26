import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';

import '../../../app/route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../assets/physical/ui/physical_asset_create_sheet.dart';

/// Wealth-scoped quick-add panel.
///
/// Surfaced from the Wealth hub's "+" header action. Lists only the
/// **structural** entries — anything that creates a new wealth
/// container or asset / liability instance. Activities (record an
/// expense, log a trade, transfer cash) live on the Activity page's
/// action panel instead, so this menu reads as "what kind of thing am
/// I adding to my net worth?".
///
/// Renamed from `showAccountsActionPanel` under the IA contract — the
/// l10n strings still use the legacy `accountsAction*` keys (their
/// English / Chinese copy is correct regardless of the hub label).
Future<void> showWealthActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.accountsActionsTitle,
    builder: (sheetContext) => AppActionSheetList(
      children: [
        AppActionSheetTile(
          icon: FLucideIcons.landmark,
          title: l10n.accountFormCreateTitle,
          subtitle: l10n.accountsActionAccountHint,
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.wealthAccountNew),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.wallet,
          title: l10n.assetsAddCashTitle,
          subtitle: l10n.assetsAddCashSubtitle,
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.wealthNewCash),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.piggyBank,
          title: l10n.assetsAddDepositTitle,
          subtitle: l10n.assetsAddDepositSubtitle,
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.wealthNewDeposit),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.chartLine,
          title: l10n.assetsAddWealthTitle,
          subtitle: l10n.assetsAddWealthSubtitle,
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.wealthNewWealth),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.house,
          title: l10n.physicalAssetAddRealEstate,
          subtitle: l10n.assetsAddRealEstateSubtitle,
          onPress: () => _closeAndOpenPhysical(
            sheetContext,
            context,
            AssetType.realEstate,
          ),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.car,
          title: l10n.physicalAssetAddVehicle,
          subtitle: l10n.assetsAddVehicleSubtitle,
          onPress: () =>
              _closeAndOpenPhysical(sheetContext, context, AssetType.vehicle),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.banknote,
          title: l10n.superFabLiability,
          subtitle: l10n.accountsActionLiabilityHint,
          onPress: () => _closeAndPush(
            sheetContext,
            context,
            AppRoutes.wealthLiabilityNew,
          ),
        ),
      ],
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
      AppRouteNames.wealthPhysicalDetail,
      pathParameters: {'id': created.id},
    );
  }
}
