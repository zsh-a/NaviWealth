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
          onTap: () => context.goNamed(SettingsRouteNames.devices),
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
    await showAppSheet<bool>(
      context: context,
      title: l10n.settingsSwitchToLocalConfirmTitle,
      builder: (_) => const _SwitchToLocalSheetBody(),
      footer: const _SwitchToLocalSheetFooter(),
    );
  }
}

/// Sheet body for confirming the cloud -> local-only downgrade.
class _SwitchToLocalSheetBody extends StatelessWidget {
  const _SwitchToLocalSheetBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Text(
      l10n.settingsSwitchToLocalConfirmBody,
      style: context.bodyCaptionStyle,
    );
  }
}

class _SwitchToLocalSheetFooter extends ConsumerStatefulWidget {
  const _SwitchToLocalSheetFooter();

  @override
  ConsumerState<_SwitchToLocalSheetFooter> createState() =>
      _SwitchToLocalSheetFooterState();
}

class _SwitchToLocalSheetFooterState
    extends ConsumerState<_SwitchToLocalSheetFooter> {
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await ref.read(auth_providers.switchToLocalOnlyProvider)();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheetFooter(
      cancelLabel: l10n.commonCancel,
      onCancel: () => Navigator.of(context).pop(false),
      submitLabel: l10n.settingsSwitchToLocal,
      onSubmit: _confirm,
      busy: _busy,
    );
  }
}
