part of 'home_page.dart';

enum HomeQuickActionMode {
  /// Empty-data state: help the user establish their financial baseline.
  onboarding,

  /// Established state: keep only the highest-frequency capture action.
  active,
}

class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({super.key, required this.mode});

  final HomeQuickActionMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (mode) {
      HomeQuickActionMode.onboarding => _OnboardingQuickActions(l10n: l10n),
      HomeQuickActionMode.active => _PrimaryQuickAction(
        icon: FLucideIcons.receiptText,
        label: l10n.homeQuickRecordEntry,
        onPress: () => context.push(FinanceRoutes.expenseNew),
      ),
    };
  }
}

class _OnboardingQuickActions extends StatelessWidget {
  const _OnboardingQuickActions({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return HomeSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s4,
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
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s6,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: AppMotionPolicy.duration(context, Motion.fast),
                width: AppSpacing.s28,
                height: AppSpacing.s28,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: AppOpacity.faint),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: AppIconSizes.sm, color: colors.primary),
              ),
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

class _PrimaryQuickAction extends StatelessWidget {
  const _PrimaryQuickAction({
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
    return HomeSurface(
      padding: EdgeInsets.zero,
      child: Semantics(
        button: true,
        label: label,
        child: FTappable(
          onPress: onPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.s28,
                    height: AppSpacing.s28,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(
                        alpha: AppOpacity.subtle,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: AppIconSizes.sm,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Text(
                      label,
                      style: context.mediumLabelStyle.copyWith(
                        color: colors.foreground,
                      ),
                    ),
                  ),
                  Icon(
                    FLucideIcons.chevronRight,
                    size: AppIconSizes.xs,
                    color: colors.mutedForeground,
                  ),
                ],
              ),
            ),
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
      color: color.withValues(alpha: AppOpacity.subtle),
    );
  }
}
