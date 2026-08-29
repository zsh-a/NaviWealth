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
      HomeQuickActionMode.active => _ActiveQuickActions(l10n: l10n),
    };
  }
}

class _ActiveQuickActions extends StatelessWidget {
  const _ActiveQuickActions({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return _AdaptiveQuickActions(
      actions: [
        _HomeQuickActionData(
          icon: FLucideIcons.upload,
          label: l10n.homeQuickImport,
          onPress: () => context.push(FinanceRoutes.activityIngest),
        ),
        _HomeQuickActionData(
          icon: FLucideIcons.receiptText,
          label: l10n.homeQuickRecordEntry,
          onPress: () => context.push(FinanceRoutes.expenseNew),
        ),
        _HomeQuickActionData(
          icon: FLucideIcons.arrowLeftRight,
          label: l10n.superFabTransfer,
          onPress: () => context.push(FinanceRoutes.transfer),
        ),
      ],
    );
  }
}

class _OnboardingQuickActions extends ConsumerWidget {
  const _OnboardingQuickActions({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AdaptiveQuickActions(
      actions: [
        _HomeQuickActionData(
          icon: FLucideIcons.walletCards,
          label: l10n.homeQuickAddAccount,
          onPress: () {
            ref
                .read(productMetricsProvider.notifier)
                .record(ProductFunnelEvent.activationStarted);
            context.push(FinanceRoutes.wealthAccountNew);
          },
        ),
        _HomeQuickActionData(
          icon: FLucideIcons.upload,
          label: l10n.homeQuickImport,
          onPress: () {
            ref
                .read(productMetricsProvider.notifier)
                .record(ProductFunnelEvent.activationStarted);
            context.push(FinanceRoutes.activityIngest);
          },
        ),
      ],
    );
  }
}

class _HomeQuickActionData {
  const _HomeQuickActionData({
    required this.icon,
    required this.label,
    required this.onPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;
}

class _AdaptiveQuickActions extends StatelessWidget {
  const _AdaptiveQuickActions({required this.actions});

  static const _stackedBreakpoint = Breakpoints.compactModule;

  final List<_HomeQuickActionData> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return HomeSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s4,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _stackedBreakpoint) {
            return Column(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  _CompactHomeQuickAction(action: actions[i]),
                  if (i != actions.length - 1)
                    _QuickActionDivider(color: colors.border, horizontal: true),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                Expanded(
                  child: _HomeQuickAction(
                    icon: actions[i].icon,
                    label: actions[i].label,
                    onPress: actions[i].onPress,
                  ),
                ),
                if (i != actions.length - 1)
                  _QuickActionDivider(color: colors.border),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CompactHomeQuickAction extends StatelessWidget {
  const _CompactHomeQuickAction({required this.action});

  final _HomeQuickActionData action;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      label: action.label,
      child: AppTappable(
        onPress: action.onPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
            child: Row(
              children: [
                AppIconTile(
                  icon: action.icon,
                  color: colors.primary,
                  size: AppSpacing.s32,
                  iconSize: AppIconSizes.sm,
                  radius: AppRadius.sm,
                  backgroundOpacity: AppOpacity.faint,
                  foregroundOpacity: 1,
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.labelStyle,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.sm,
                  color: colors.mutedForeground.withValues(
                    alpha: AppOpacity.disabled,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    return AppTappable(
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
              AppIconTile(
                icon: icon,
                color: colors.primary,
                size: AppSpacing.s28,
                iconSize: AppIconSizes.sm,
                radius: AppRadius.sm,
                backgroundOpacity: AppOpacity.faint,
                foregroundOpacity: 1,
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

class _QuickActionDivider extends StatelessWidget {
  const _QuickActionDivider({required this.color, this.horizontal = false});

  final Color color;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return Container(
        height: AppStroke.hairline,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s48),
        color: color.withValues(alpha: AppOpacity.subtle),
      );
    }
    return Container(
      width: AppStroke.hairline,
      height: AppSpacing.s24,
      color: color.withValues(alpha: AppOpacity.subtle),
    );
  }
}
