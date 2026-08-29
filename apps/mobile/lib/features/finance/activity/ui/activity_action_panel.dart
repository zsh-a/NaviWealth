import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Activity-scoped quick-add panel.
///
/// Surfaced from the Activity page's "+" header action. Import is the primary
/// capture path; the explicit flow forms remain available as fast fallbacks.
/// Structural creation (new account, asset, or liability) stays in Wealth.
Future<void> showActivityActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.activityActionsTitle,
    builder: (sheetContext) => AppActionSheetList(
      children: [
        AppActionSheetTile(
          icon: FLucideIcons.upload,
          title: l10n.homeQuickImport,
          subtitle: l10n.activityActionImportHint,
          onPress: () => _closeAndPush(
            sheetContext,
            context,
            FinanceRoutes.activityIngest,
          ),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.creditCard,
          title: l10n.superFabExpense,
          subtitle: l10n.activityActionExpenseHint,
          onPress: () =>
              _closeAndPush(sheetContext, context, FinanceRoutes.expenseNew),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.banknote,
          title: l10n.superFabIncome,
          subtitle: l10n.activityActionIncomeHint,
          onPress: () =>
              _closeAndPush(sheetContext, context, FinanceRoutes.incomeNew),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.chartLine,
          title: l10n.superFabTrade,
          subtitle: l10n.activityActionTradeHint,
          onPress: () =>
              _closeAndPush(sheetContext, context, FinanceRoutes.tradeEntry),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.arrowLeftRight,
          title: l10n.superFabTransfer,
          subtitle: l10n.activityActionTransferHint,
          onPress: () =>
              _closeAndPush(sheetContext, context, FinanceRoutes.transfer),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.arrowLeftRight,
          title: l10n.superFabConvert,
          subtitle: l10n.activityActionConvertHint,
          onPress: () => _closeAndPush(
            sheetContext,
            context,
            '${FinanceRoutes.transfer}?convert=1',
          ),
        ),
      ],
    ),
  );
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
