import 'package:flutter/material.dart' show Icons, Navigator;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
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
        _ActionTile(
          icon: Icons.add_card_outlined,
          title: l10n.superFabExpense,
          subtitle: l10n.activityActionExpenseHint,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.expenseNew),
        ),
        _ActionTile(
          icon: Icons.add_chart_outlined,
          title: l10n.superFabTrade,
          subtitle: l10n.activityActionTradeHint,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.tradeEntry),
        ),
        _ActionTile(
          icon: Icons.swap_horiz,
          title: l10n.superFabTransfer,
          subtitle: l10n.activityActionTransferHint,
          onTap: () =>
              _closeAndPush(sheetContext, context, AppRoutes.transfer),
        ),
        _ActionTile(
          icon: Icons.currency_exchange,
          title: l10n.superFabConvert,
          subtitle: l10n.activityActionConvertHint,
          onTap: () => _closeAndPush(
            sheetContext,
            context,
            '${AppRoutes.transfer}?convert=1',
          ),
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
