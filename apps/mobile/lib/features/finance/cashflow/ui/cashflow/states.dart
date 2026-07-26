part of '../cashflow_page.dart';

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.wallet,
      title: l10n.cashFlowEmptyTitle,
      message: l10n.cashFlowEmptyBody,
      iconSize: AppIconSizes.heroLg,
    );
  }
}
