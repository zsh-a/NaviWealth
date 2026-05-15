import 'package:flutter/material.dart' show Icons, Navigator;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Activity-scoped quick-add panel.
///
/// Surfaced from the Activity page's "+" header action. Lists only the
/// **flow** entries — things that record what happened (expense, trade,
/// transfer, currency convert). Structural creation (new account, new
/// asset, new liability) lives on the Accounts hub instead, so the
/// action menu stays mentally bucketed: Activity = "log a fact",
/// Accounts = "set up the container".
Future<void> showActivityActionPanel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.activityActionsTitle,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppActionSheetTile(
          icon: Icons.add_card_outlined,
          title: l10n.superFabExpense,
          subtitle: l10n.activityActionExpenseHint,
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.expenseNew),
        ),
        AppActionSheetTile(
          icon: Icons.add_chart_outlined,
          title: l10n.superFabTrade,
          subtitle: l10n.activityActionTradeHint,
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.tradeEntry),
        ),
        AppActionSheetTile(
          icon: Icons.swap_horiz,
          title: l10n.superFabTransfer,
          subtitle: l10n.activityActionTransferHint,
          onPress: () =>
              _closeAndPush(sheetContext, context, AppRoutes.transfer),
        ),
        AppActionSheetTile(
          icon: Icons.currency_exchange,
          title: l10n.superFabConvert,
          subtitle: l10n.activityActionConvertHint,
          onPress: () => _closeAndPush(
            sheetContext,
            context,
            '${AppRoutes.transfer}?convert=1',
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
