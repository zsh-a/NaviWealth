import 'package:flutter/material.dart' show Icons, Navigator;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../data/domain/enums.dart';
import '../design_system/design_system.dart';
import '../features/assets/physical/ui/physical_asset_create_sheet.dart';
import '../l10n/gen/app_localizations.dart';
import 'route_paths.dart';

/// Global "+" action panel — surfaced from every page-level header.
/// Routes through [showAppSheet] so the chrome (drag handle, title row,
/// padding) matches every other modal sheet in the app.
Future<void> showGlobalActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.globalActionPanelTitle,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTile(
          icon: Icons.add_card_outlined,
          title: l10n.superFabExpense,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.expenseNew),
        ),
        _SheetTile(
          icon: Icons.add_chart_outlined,
          title: l10n.superFabTrade,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.tradeEntry),
        ),
        _SheetTile(
          icon: Icons.account_balance_wallet_outlined,
          title: l10n.superFabAsset,
          onTap: () {
            Navigator.of(sheetContext).pop();
            showAssetActionPanel(context);
          },
        ),
        _SheetTile(
          icon: Icons.swap_horiz,
          title: l10n.superFabTransfer,
          subtitle: l10n.superFabTransferSubtitle,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.transfer),
        ),
        _SheetTile(
          icon: Icons.currency_exchange,
          title: l10n.superFabConvert,
          subtitle: l10n.superFabConvertSubtitle,
          onTap: () => _closeAndPush(
            sheetContext,
            context,
            '${AppRoutes.transfer}?convert=1',
          ),
        ),
        _SheetTile(
          icon: Icons.add_card_outlined,
          title: l10n.accountFormCreateTitle,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountListNew),
        ),
        _SheetTile(
          icon: Icons.payments_outlined,
          title: l10n.superFabLiability,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.liabilityNew),
        ),
      ],
    ),
  );
}

Future<void> showAssetActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.assetsAddSheetTitle,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTile(
          icon: Icons.account_balance_wallet_outlined,
          title: l10n.assetsAddCashTitle,
          subtitle: l10n.assetsAddCashSubtitle,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountNewCash),
        ),
        _SheetTile(
          icon: Icons.savings_outlined,
          title: l10n.assetsAddDepositTitle,
          subtitle: l10n.assetsAddDepositSubtitle,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountNewDeposit),
        ),
        _SheetTile(
          icon: Icons.auto_graph_outlined,
          title: l10n.assetsAddWealthTitle,
          subtitle: l10n.assetsAddWealthSubtitle,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.accountNewWealth),
        ),
        _SheetTile(
          icon: Icons.home_outlined,
          title: l10n.physicalAssetAddRealEstate,
          subtitle: l10n.assetsAddRealEstateSubtitle,
          onTap: () =>
              _closeAndOpenPhysical(sheetContext, context, AssetType.realEstate),
        ),
        _SheetTile(
          icon: Icons.directions_car_outlined,
          title: l10n.physicalAssetAddVehicle,
          subtitle: l10n.assetsAddVehicleSubtitle,
          onTap: () =>
              _closeAndOpenPhysical(sheetContext, context, AssetType.vehicle),
        ),
      ],
    ),
  );
}

/// One row in a sheet menu — single-line layout with optional subtitle
/// rendered as a muted second line. Lighter than `FTile` (no border /
/// elevation) so the rows dissolve into the AppSheet surface.
class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
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
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtitle!,
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
