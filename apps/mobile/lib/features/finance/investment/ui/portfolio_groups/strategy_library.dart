part of '../portfolio_group_sheets.dart';

Future<void> showPortfolioStrategyLibrarySheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioStrategyLibraryTitle,
    subtitle: l10n.portfolioStrategyLibrarySubtitle,
    builder: (_) => const _PortfolioStrategyLibrary(),
  );
}

class _PortfolioStrategyLibrary extends ConsumerWidget {
  const _PortfolioStrategyLibrary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final templates = ref.watch(portfolioStrategyTemplatesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FButton(
          onPress: () => showCustomPortfolioStrategyTemplateSheet(context),
          prefix: const Icon(FLucideIcons.plus),
          child: Text(l10n.portfolioStrategyCustomCreateAction),
        ),
        const SizedBox(height: AppSpacing.s12),
        switch (templates) {
          AsyncData(value: final items) => Column(
            children: [
              for (final template in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                  child: SoftCard.flat(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  template.displayName(languageCode),
                                  style: context.theme.typography.body.sm,
                                ),
                                Text(
                                  template.isBuiltIn
                                      ? l10n.portfolioStrategyBuiltInBadge
                                      : l10n.portfolioStrategyCustomBadge,
                                  style: context.captionStyle,
                                ),
                              ],
                            ),
                          ),
                          if (!template.isBuiltIn) ...[
                            FButton(
                              variant: FButtonVariant.ghost,
                              onPress: () =>
                                  showCustomPortfolioStrategyTemplateSheet(
                                    context,
                                    existing: template,
                                  ),
                              child: Text(l10n.portfolioStrategyEditAction),
                            ),
                            FButton(
                              variant: FButtonVariant.ghost,
                              onPress: () => _archiveStrategyTemplate(
                                context,
                                ref,
                                template,
                              ),
                              child: Text(l10n.portfolioStrategyArchiveAction),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          AsyncError(:final error, :final stackTrace) => AppEmptyState.error(
            title: l10n.portfolioStrategyLibraryTitle,
            message: userSafeErrorMessage(
              context,
              error,
              stackTrace: stackTrace,
              operation: 'load strategy library',
            ),
          ),
          _ => const Center(child: FCircularProgress()),
        },
      ],
    );
  }

  Future<void> _archiveStrategyTemplate(
    BuildContext context,
    WidgetRef ref,
    PortfolioStrategyTemplate template,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.portfolioStrategyArchiveTitle),
      body: Text(l10n.portfolioStrategyArchiveBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.portfolioStrategyArchiveAction,
      icon: FLucideIcons.archive,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.archiveCustomStrategyTemplate(template);
    } catch (_) {
      if (context.mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.portfolioStrategyArchiveFailed,
        );
      }
    }
  }
}
