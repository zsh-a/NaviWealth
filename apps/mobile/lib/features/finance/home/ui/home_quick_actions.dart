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
            context.push(FinanceRoutes.wealthAccountNew);
          },
        ),
        _HomeQuickActionData(
          icon: FLucideIcons.upload,
          label: l10n.homeQuickImport,
          onPress: () {
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

  final List<_HomeQuickActionData> actions;

  double _horizontalWidth(BuildContext context) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var widest = 0.0;
    for (final action in actions) {
      painter.text = TextSpan(
        text: action.label,
        style: context.appTheme.type.label,
      );
      painter.layout();
      if (painter.width > widest) widest = painter.width;
    }
    painter.dispose();
    return (widest + AppSpacing.s56) * actions.length +
        AppSpacing.s8 * (actions.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    Widget button(int index) {
      final action = actions[index];
      return AppActionButton(
        onPress: action.onPress,
        hapticIntent: AppInteractionIntent.navigate,
        emphasis: index == 0
            ? AppButtonEmphasis.filled
            : AppButtonEmphasis.tonal,
        variant: index == 0 ? FButtonVariant.primary : FButtonVariant.secondary,
        size: FButtonSizeVariant.md,
        mainAxisSize: MainAxisSize.max,
        prefix: Icon(action.icon, size: AppIconSizes.sm),
        child: Flexible(child: Text(action.label, textAlign: TextAlign.center)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _horizontalWidth(context)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.s8),
                button(i),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.s8),
              Expanded(child: button(i)),
            ],
          ],
        );
      },
    );
  }
}
