part of 'settings_overview.dart';

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final marketMode = ref.watch(marketColorModeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return Column(
      children: [
        InlineSettingRow<ThemeMode>(
          icon: FLucideIcons.sunMoon,
          label: l10n.settingsThemeModeTitle,
          value: themeMode,
          options: {
            for (final m in ThemeMode.values) _themeModeLabel(l10n, m): m,
          },
          onChanged: (m) {
            Haptics.selection();
            ref.read(themeModeProvider.notifier).set(m);
          },
        ),
        const AppGradientDivider(),
        InlineSettingRow<MarketColorMode>(
          icon: FLucideIcons.arrowUpDown,
          label: l10n.settingsMarketColorTitle,
          value: marketMode,
          options: {
            for (final m in MarketColorMode.values)
              _marketModeLabel(l10n, m): m,
          },
          stackValue: true,
          onChanged: (m) => ref.read(marketColorModeProvider.notifier).set(m),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.s14,
            0,
            AppSpacing.s14,
            AppSpacing.s8,
          ),
          child: _MarketColorPreview(),
        ),
        const AppGradientDivider(),
        InlineSettingRow<String>(
          icon: FLucideIcons.languages,
          label: l10n.settingsLanguageTitle,
          value: locale?.languageCode ?? '',
          options: {
            l10n.langSystem: '',
            l10n.langEnglish: 'en',
            l10n.langChinese: 'zh',
          },
          onChanged: (picked) {
            Haptics.selection();
            ref
                .read(localeProvider.notifier)
                .set(picked.isEmpty ? null : Locale(picked));
          },
        ),
      ],
    );
  }

  String _themeModeLabel(AppLocalizations l10n, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.system => l10n.themeModeSystem,
        ThemeMode.light => l10n.themeModeLight,
        ThemeMode.dark => l10n.themeModeDark,
      };

  String _marketModeLabel(AppLocalizations l10n, MarketColorMode mode) =>
      switch (mode) {
        MarketColorMode.redUpGreenDown => l10n.marketColorRedUpGreenDown,
        MarketColorMode.greenUpRedDown => l10n.marketColorGreenUpRedDown,
        MarketColorMode.colorblind => l10n.marketColorColorblind,
      };
}

class _AboutTile extends ConsumerWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final versionAsync = ref.watch(appVersionProvider);
    final colors = context.theme.colors;
    final subtitle = versionAsync.when(
      loading: () => l10n.settingsAboutSubtitle('…'),
      error: (_, _) => l10n.settingsAboutSubtitle('?'),
      data: (info) {
        final base = l10n.settingsAboutSubtitle(
          '${info.version}+${info.buildNumber}',
        );
        if (info.commitSha == 'dev' || info.commitSha.isEmpty) return base;
        final shortSha = info.commitSha.length >= 7
            ? info.commitSha.substring(0, 7)
            : info.commitSha;
        return '$base · $shortSha';
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s10,
      ),
      child: Row(
        children: [
          Icon(
            FLucideIcons.info,
            size: AppIconSizes.h18,
            color: colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.settingsAboutTitle,
                  style: context.theme.typography.body.sm,
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(subtitle, style: context.captionStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketColorPreview extends StatelessWidget {
  const _MarketColorPreview();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        DeltaChip(value: 1.23, format: DeltaFormat.percent),
        DeltaChip(value: -0.42, format: DeltaFormat.percent),
        DeltaChip(value: 0, format: DeltaFormat.percent),
      ],
    );
  }
}

/// Opt-in toggle for anonymous crash + breadcrumb telemetry. Defaults to OFF:
/// flipping this only takes
/// effect on the next error captured, not retroactively, and even when
/// enabled it stays a no-op until the Sentry integration registers a
/// real [crashReporterDelegateProvider].
class _CrashReportingRow extends ConsumerWidget {
  const _CrashReportingRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(crashReportingEnabledProvider);
    return InlineSwitchRow(
      icon: FLucideIcons.bug,
      label: l10n.settingsCrashReportingTitle,
      subtitle: l10n.settingsCrashReportingSubtitle,
      value: enabled,
      onChanged: (next) =>
          ref.read(crashReportingEnabledProvider.notifier).setEnabled(next),
    );
  }
}

class _ProductMetricsRow extends ConsumerWidget {
  const _ProductMetricsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(productMetricsProvider);
    return Column(
      children: [
        InlineSwitchRow(
          icon: FLucideIcons.chartNoAxesColumnIncreasing,
          label: l10n.settingsProductMetricsTitle,
          subtitle: l10n.settingsProductMetricsSubtitle,
          value: enabled,
          onChanged: (next) =>
              ref.read(productMetricsProvider.notifier).setEnabled(next),
        ),
        if (enabled) ...[
          const AppGradientDivider(),
          InlineLinkRow(
            icon: FLucideIcons.copy,
            label: l10n.settingsProductMetricsCopy,
            subtitle: l10n.settingsProductMetricsCopySubtitle,
            onTap: () async {
              final report = ref
                  .read(productMetricsProvider.notifier)
                  .exportAggregates();
              await Clipboard.setData(ClipboardData(text: jsonEncode(report)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.settingsProductMetricsCopied)),
                );
              }
            },
          ),
        ],
      ],
    );
  }
}

class _BiometricUnlockRow extends ConsumerStatefulWidget {
  const _BiometricUnlockRow();

  @override
  ConsumerState<_BiometricUnlockRow> createState() =>
      _BiometricUnlockRowState();
}

class _BiometricUnlockRowState extends ConsumerState<_BiometricUnlockRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(biometricUnlockEnabledProvider);
    final availability = ref.watch(biometricAvailabilityProvider);
    final subtitle = availability.when(
      data: (value) => switch (value) {
        BiometricAvailability.available => l10n.settingsBiometricSubtitle,
        BiometricAvailability.notEnrolled => l10n.settingsBiometricNotEnrolled,
        BiometricAvailability.unsupported => l10n.settingsBiometricUnavailable,
      },
      loading: () => l10n.settingsBiometricChecking,
      error: (_, _) => l10n.settingsBiometricUnavailable,
    );
    return InlineSwitchRow(
      icon: FLucideIcons.fingerprint,
      label: l10n.settingsBiometricTitle,
      subtitle: _busy ? l10n.settingsBiometricChecking : subtitle,
      value: enabled,
      onChanged: (next) => _setEnabled(next),
    );
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    if (!enabled) {
      await ref.read(biometricUnlockEnabledProvider.notifier).setEnabled(false);
      ref.read(biometricUnlockSessionProvider.notifier).lock();
      return;
    }

    setState(() => _busy = true);
    final availability = await ref.read(biometricAvailabilityProvider.future);
    if (!mounted) return;
    if (availability != BiometricAvailability.available) {
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        availability == BiometricAvailability.notEnrolled
            ? l10n.settingsBiometricNotEnrolled
            : l10n.settingsBiometricUnavailable,
      );
      return;
    }

    final ok = await ref
        .read(biometricAuthServiceProvider)
        .authenticate(reason: l10n.biometricUnlockReason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      AppMessenger.show(context, ToastKind.error, l10n.biometricUnlockFailed);
      return;
    }
    await ref.read(biometricUnlockEnabledProvider.notifier).setEnabled(true);
    ref.read(biometricUnlockSessionProvider.notifier).unlock();
  }
}
