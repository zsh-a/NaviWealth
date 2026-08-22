part of '../investment_portfolio_sheets.dart';

class PortfolioLotAssignmentPage extends StatelessWidget {
  const PortfolioLotAssignmentPage({super.key, this.preferredGroupId});

  final String? preferredGroupId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _PortfolioAssignmentPageFrame(
      title: l10n.portfolioAssignLotsTitle,
      subtitle: l10n.portfolioAssignLotsSubtitle,
      child: _PortfolioLotAssignmentLoader(preferredGroupId: preferredGroupId),
    );
  }
}

class PortfolioCashAssignmentPage extends StatelessWidget {
  const PortfolioCashAssignmentPage({
    super.key,
    this.preferredGroupId,
    this.suggestedAmount,
  });

  final String? preferredGroupId;
  final Decimal? suggestedAmount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _PortfolioAssignmentPageFrame(
      title: l10n.portfolioAssignCashTitle,
      subtitle: l10n.portfolioAssignCashSubtitle,
      child: _PortfolioCashAssignmentLoader(
        preferredGroupId: preferredGroupId,
        suggestedAmount: suggestedAmount,
      ),
    );
  }
}

class _PortfolioAssignmentPageFrame extends StatelessWidget {
  const _PortfolioAssignmentPageFrame({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: title,
      childPad: false,
      child: AdaptiveContentFrame(
        maxWidth: AdaptiveMaxWidth.narrow,
        expandSinglePrimary: true,
        padding: shellTabContentPadding(
          context,
          left: AppSpacing.s16,
          top: AppSpacing.s12,
          right: AppSpacing.s16,
          bottom: AppSpacing.s24,
        ),
        primary: ListView(
          children: [
            Text(subtitle, style: context.captionStyle),
            const SizedBox(height: AppSpacing.s20),
            child,
          ],
        ),
      ),
    );
  }
}
