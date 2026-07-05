part of '../cashflow_page.dart';

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FLucideIcons.circleAlert,
            color: context.theme.colors.destructive,
            size: AppIconSizes.xl,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: onRetry,
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}

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
