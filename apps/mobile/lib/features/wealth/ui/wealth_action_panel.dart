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
    subtitle: l10n.wealthActionPanelSubtitle,
    maxHeightFactor: 0.9,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WealthActionSection(
          title: l10n.wealthActionPanelAccountsGroup,
          actions: [
            _WealthAction(
              icon: FLucideIcons.landmark,
              title: l10n.accountFormCreateTitle,
              subtitle: l10n.accountsActionAccountHint,
              onPress: () => _closeAndPush(
                sheetContext,
                context,
                AppRoutes.wealthAccountNew,
              ),
            ),
            _WealthAction(
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
        const SizedBox(height: AppSpacing.s16),
        _WealthActionSection(
          title: l10n.wealthActionPanelFinancialGroup,
          actions: [
            _WealthAction(
              icon: FLucideIcons.wallet,
              title: l10n.assetsAddCashTitle,
              subtitle: l10n.assetsAddCashSubtitle,
              onPress: () =>
                  _closeAndPush(sheetContext, context, AppRoutes.wealthNewCash),
            ),
            _WealthAction(
              icon: FLucideIcons.piggyBank,
              title: l10n.assetsAddDepositTitle,
              subtitle: l10n.assetsAddDepositSubtitle,
              onPress: () => _closeAndPush(
                sheetContext,
                context,
                AppRoutes.wealthNewDeposit,
              ),
            ),
            _WealthAction(
              icon: FLucideIcons.chartLine,
              title: l10n.assetsAddWealthTitle,
              subtitle: l10n.assetsAddWealthSubtitle,
              onPress: () => _closeAndPush(
                sheetContext,
                context,
                AppRoutes.wealthNewWealth,
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
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.s4),
          child: Text(
            title,
            style: context.theme.typography.xs.copyWith(
              fontWeight: FontWeight.w600,
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 360 ? 2 : 1;
            final itemWidth = cols == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - AppSpacing.s8) / 2;
            return Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: itemWidth,
                    child: _WealthActionTile(action: action),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WealthActionTile extends StatelessWidget {
  const _WealthActionTile({required this.action});

  final _WealthAction action;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      onPress: action.onPress,
      padding: const EdgeInsets.all(AppSpacing.s10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: AppSpacing.s40,
            height: AppSpacing.s40,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              action.icon,
              size: AppIconSizes.h18,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  action.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.xs2.copyWith(
                    color: colors.mutedForeground,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s6),
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.sm,
            color: colors.mutedForeground.withValues(alpha: 0.55),
          ),
        ],
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
      AppRouteNames.wealthPhysicalDetail,
      pathParameters: {'id': created.id},
    );
  }
}
