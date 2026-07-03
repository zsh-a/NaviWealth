part of 'dividend_center_page.dart';

class _EmptyDividendState extends StatelessWidget {
  const _EmptyDividendState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.banknote,
      title: l10n.dividendCenterEmptyTitle,
      message: l10n.dividendCenterEmptyBody,
      action: FButton(
        key: const Key('dividend-center-record-cta'),
        onPress: () => context.push(FinanceRoutes.wealthCorporateAction),
        child: Text(l10n.dividendCenterRecordAction),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: context.rowTitleStyle)),
        if (trailing != null) Text(trailing!, style: context.captionStyle),
      ],
    );
  }
}
