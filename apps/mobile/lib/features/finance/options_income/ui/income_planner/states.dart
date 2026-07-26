part of 'income_planner_page.dart';

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: FCircularProgress());
  }
}

class _UnsupportedOnWebPage extends StatelessWidget {
  const _UnsupportedOnWebPage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.incomePlannerTitle,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Text(l10n.incomePlannerUnsupportedOnWeb),
      ),
    );
  }
}

class _StartState extends ConsumerWidget {
  const _StartState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FLucideIcons.candlestickChart,
              size: AppIconSizes.hero,
              color: colors.mutedForeground,
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(l10n.incomePlannerStartTitle, style: context.titleLabelStyle),
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.incomePlannerStartBody,
              textAlign: TextAlign.center,
              style: context.bodyCaptionStyle,
            ),
            const SizedBox(height: AppSpacing.s20),
            FButton(
              onPress: () => _startSetup(context),
              child: Flexible(
                child: Text(
                  l10n.incomePlannerStartCta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startSetup(BuildContext context) async {
    final accepted = await showOccDisclosureSheet(context);
    if (!accepted || !context.mounted) return;
    await showStrategyProfileSheet(context);
    if (!context.mounted) return;
    await showApprovedUnderlyingSheet(context);
  }
}
