import 'package:flutter/material.dart' show Icons, Navigator;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../data/domain/enums.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../assets/physical/ui/physical_asset_create_sheet.dart';

/// Accounts-scoped quick-add panel.
///
/// Surfaced from the Accounts hub's "+" header action. Lists only the
/// **structural** entries — anything that creates a new wealth
/// container or asset / liability instance. Activities (record an
/// expense, log a trade, transfer cash) live on the Activity page's
/// action panel instead, so this menu reads as "what kind of thing am
/// I adding to my net worth?".
Future<void> showAccountsActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.accountsActionsTitle,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionTile(
          icon: Icons.account_balance_outlined,
          title: l10n.accountFormCreateTitle,
          subtitle: l10n.accountsActionAccountHint,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountListNew),
        ),
        _ActionTile(
          icon: Icons.account_balance_wallet_outlined,
          title: l10n.assetsAddCashTitle,
          subtitle: l10n.assetsAddCashSubtitle,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountNewCash),
        ),
        _ActionTile(
          icon: Icons.savings_outlined,
          title: l10n.assetsAddDepositTitle,
          subtitle: l10n.assetsAddDepositSubtitle,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountNewDeposit),
        ),
        _ActionTile(
          icon: Icons.auto_graph_outlined,
          title: l10n.assetsAddWealthTitle,
          subtitle: l10n.assetsAddWealthSubtitle,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountNewWealth),
        ),
        _ActionTile(
          icon: Icons.home_outlined,
          title: l10n.physicalAssetAddRealEstate,
          subtitle: l10n.assetsAddRealEstateSubtitle,
          onTap: () =>
              _closeAndOpenPhysical(sheetContext, context, AssetType.realEstate),
        ),
        _ActionTile(
          icon: Icons.directions_car_outlined,
          title: l10n.physicalAssetAddVehicle,
          subtitle: l10n.assetsAddVehicleSubtitle,
          onTap: () =>
              _closeAndOpenPhysical(sheetContext, context, AssetType.vehicle),
        ),
        _ActionTile(
          icon: Icons.payments_outlined,
          title: l10n.superFabLiability,
          subtitle: l10n.accountsActionLiabilityHint,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.liabilityNew),
        ),
      ],
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.foreground.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: colors.mutedForeground),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: context.theme.typography.sm.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      subtitle,
                      style: context.theme.typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
