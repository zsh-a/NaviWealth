part of 'settings_overview.dart';

class _AccountSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isLocalOnly =
        ref.watch(auth_providers.authStateProvider) is AuthLocalOnly;

    if (isLocalOnly) {
      return InlineLinkRow(
        icon: FLucideIcons.smartphone,
        label: l10n.settingsAccountLocalOnlyBadge,
        subtitle: l10n.settingsUpgradeToCloudHint,
        trailing: Icon(
          FLucideIcons.cloud,
          size: AppIconSizes.h18,
          color: context.theme.colors.primary,
        ),
        onTap: () => context.go('${AuthRoutes.login}?mode=upgrade'),
      );
    }
    return Column(
      children: [
        InlineLinkRow(
          icon: FLucideIcons.monitor,
          label: l10n.settingsDevicesTitle,
          subtitle: l10n.settingsDevicesSubtitle,
          onTap: () => context.pushNamed(SettingsRouteNames.devices),
        ),
        const AppGradientDivider(),
        InlineLinkRow(
          icon: FLucideIcons.logOut,
          label: l10n.settingsSignOutTitle,
          subtitle: l10n.settingsSignOutSubtitle,
          onTap: () => _showSwitchToLocalSheet(context, ref),
        ),
      ],
    );
  }

  static Future<void> _showSwitchToLocalSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.settingsSwitchToLocalConfirmTitle),
      body: Text(l10n.settingsSwitchToLocalConfirmBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.settingsSwitchToLocal,
    );
    if (confirmed != true || !context.mounted) return;
    final dismiss = await showProgressDialog(
      context: context,
      message: l10n.settingsSwitchToLocal,
    );
    try {
      await ref.read(auth_providers.switchToLocalOnlyProvider)();
    } finally {
      await dismiss();
    }
  }
}
