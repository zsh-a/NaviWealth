part of 'home_page.dart';

class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return HomeSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s6,
      ),
      child: Row(
        children: [
          Expanded(
            child: _HomeQuickAction(
              icon: FLucideIcons.walletCards,
              label: l10n.homeQuickAddAccount,
              onPress: () => context.push(FinanceRoutes.wealthAccountNew),
            ),
          ),
          _QuickActionDivider(color: colors.border),
          Expanded(
            child: _HomeQuickAction(
              icon: FLucideIcons.receiptText,
              label: l10n.homeQuickRecordEntry,
              onPress: () => context.push(FinanceRoutes.expenseNew),
            ),
          ),
          _QuickActionDivider(color: colors.border),
          Expanded(
            child: _HomeQuickAction(
              icon: FLucideIcons.upload,
              label: l10n.homeQuickImport,
              onPress: () => context.push(FinanceRoutes.activityIngest),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeQuickAction extends StatelessWidget {
  const _HomeQuickAction({
    required this.icon,
    required this.label,
    required this.onPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s6,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppIconSizes.sm, color: colors.primary),
              const SizedBox(height: AppSpacing.s4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.captionLabelStyle.copyWith(
                  color: colors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionDivider extends StatelessWidget {
  const _QuickActionDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppStroke.hairline,
      height: AppSpacing.s24,
      color: color.withValues(alpha: AppOpacity.faint),
    );
  }
}
