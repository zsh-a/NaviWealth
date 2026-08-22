import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/assets/physical/ui/physical_asset_create_sheet.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../composition/finance_route_paths.dart';

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
    subtitle: l10n.wealthActionPanelSubtitle,
    maxHeightFactor: 0.9,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WealthActionSection(
          title: l10n.wealthObjectsTitle,
          actions: [
            _WealthAction(
              icon: FLucideIcons.landmark,
              title: l10n.accountFormCreateTitle,
              subtitle: l10n.accountsActionAccountHint,
              onPress: () => _closeAndPush(
                sheetContext,
                context,
                FinanceRoutes.wealthAccountNew,
              ),
            ),
            _WealthAction(
              icon: FLucideIcons.arrowDownRight,
              title: l10n.superFabLiability,
              subtitle: l10n.accountsActionLiabilityHint,
              onPress: () => _closeAndPush(
                sheetContext,
                context,
                FinanceRoutes.wealthLiabilityNew,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        _WealthActionSection(
          title: l10n.wealthActionPanelFinancialGroup,
          actions: [
            _WealthAction(
              icon: FLucideIcons.wallet,
              title: l10n.assetsAddCashTitle,
              subtitle: l10n.assetsAddCashSubtitle,
              onPress: () => _closeAndPush(
                sheetContext,
                context,
                FinanceRoutes.wealthNewCash,
              ),
            ),
            _WealthAction(
              icon: FLucideIcons.piggyBank,
              title: l10n.assetsAddDepositTitle,
              subtitle: l10n.assetsAddDepositSubtitle,
              onPress: () => _closeAndPush(
                sheetContext,
                context,
                FinanceRoutes.wealthNewDeposit,
              ),
            ),
            _WealthAction(
              icon: FLucideIcons.chartLine,
              title: l10n.assetsAddWealthTitle,
              subtitle: l10n.assetsAddWealthSubtitle,
              onPress: () => _closeAndPush(
                sheetContext,
                context,
                FinanceRoutes.wealthNewWealth,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        _WealthActionSection(
          title: l10n.wealthActionPanelPhysicalGroup,
          actions: [
            _WealthAction(
              icon: FLucideIcons.house,
              title: l10n.physicalAssetAddRealEstate,
              subtitle: l10n.assetsAddRealEstateSubtitle,
              onPress: () => _closeAndOpenPhysical(
                sheetContext,
                context,
                AssetType.realEstate,
              ),
            ),
            _WealthAction(
              icon: FLucideIcons.car,
              title: l10n.physicalAssetAddVehicle,
              subtitle: l10n.assetsAddVehicleSubtitle,
              onPress: () => _closeAndOpenPhysical(
                sheetContext,
                context,
                AssetType.vehicle,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _WealthAction {
  const _WealthAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPress;
}

class _WealthActionSection extends StatelessWidget {
  const _WealthActionSection({required this.title, required this.actions});

  final String title;
  final List<_WealthAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetSectionLabel(title),
        AppActionSheetList(
          children: [
            for (final action in actions)
              AppActionSheetTile(
                icon: action.icon,
                title: action.title,
                subtitle: action.subtitle,
                onPress: action.onPress,
              ),
          ],
        ),
      ],
    );
  }
}

Future<void> _closeAndPush(
  BuildContext sheetContext,
  BuildContext routeContext,
  String path,
) {
  return closeSheetThen(sheetContext, () {
    if (routeContext.mounted) routeContext.push(path);
  });
}

Future<void> _closeAndOpenPhysical(
  BuildContext sheetContext,
  BuildContext routeContext,
  AssetType type,
) async {
  await closeSheetThen(sheetContext, () async {
    if (!routeContext.mounted) return;
    final created = await PhysicalAssetCreateSheet.show(
      routeContext,
      type: type,
    );
    if (created != null && routeContext.mounted) {
      routeContext.goNamed(
        FinanceRouteNames.wealthPhysicalDetail,
        pathParameters: {'id': created.id},
      );
    }
  });
}
