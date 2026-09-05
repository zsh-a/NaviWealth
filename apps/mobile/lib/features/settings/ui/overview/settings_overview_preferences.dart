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
            AppInteraction.signal(AppInteractionIntent.select);
            ref.read(themeModeProvider.notifier).set(m);
          },
        ),
        const AppGroupedDivider(),
        InlineSettingRow<AppSurfaceStyle>(
          icon: FLucideIcons.palette,
          label: l10n.settingsSurfaceStyleTitle,
          value: ref.watch(surfaceStyleProvider),
          options: {
            for (final s in AppSurfaceStyle.values)
              _surfaceStyleLabel(l10n, s): s,
          },
          onChanged: (s) {
            AppInteraction.signal(AppInteractionIntent.select);
            ref.read(surfaceStyleProvider.notifier).set(s);
          },
        ),
        const AppGroupedDivider(),
        InlineSettingRow<AppAccentSeed>(
          icon: FLucideIcons.paintbrush,
          label: l10n.settingsAccentSeedTitle,
          value: ref.watch(accentSeedProvider),
          options: {
            for (final a in AppAccentSeed.values) _accentSeedLabel(l10n, a): a,
          },
          onChanged: (a) {
            AppInteraction.signal(AppInteractionIntent.select);
            ref.read(accentSeedProvider.notifier).set(a);
          },
        ),
        const AppGroupedDivider(),
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
        const AppGroupedDivider(),
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
            AppInteraction.signal(AppInteractionIntent.select);
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

  String _accentSeedLabel(AppLocalizations l10n, AppAccentSeed seed) =>
      switch (seed) {
        AppAccentSeed.cyan => l10n.accentSeedCyan,
        AppAccentSeed.violet => l10n.accentSeedViolet,
        AppAccentSeed.indigo => l10n.accentSeedIndigo,
      };

  String _surfaceStyleLabel(AppLocalizations l10n, AppSurfaceStyle style) =>
      switch (style) {
        AppSurfaceStyle.standard => l10n.surfaceStyleStandard,
        AppSurfaceStyle.oled => l10n.surfaceStyleOled,
        AppSurfaceStyle.highContrast => l10n.surfaceStyleHighContrast,
      };
}

class _AboutTile extends ConsumerStatefulWidget {
  const _AboutTile();

  @override
  ConsumerState<_AboutTile> createState() => _AboutTileState();
}

class _AboutTileState extends ConsumerState<_AboutTile> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final versionAsync = ref.watch(appVersionProvider);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SettingsIconChip(icon: FLucideIcons.info),
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
          if (isAndroidNativePlatform) ...[
            const SizedBox(height: AppSpacing.s10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FButton(
                variant: FButtonVariant.outline,
                onPress: _checking ? null : _checkForUpdates,
                child: Flexible(
                  child: Text(
                    _checking
                        ? l10n.nativeUpdateChecking
                        : l10n.nativeUpdateCheck,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await ref.read(nativeUpdateCheckProvider(true).future);
      // The forced request has refreshed the shared cache. Rebuild the global
      // banner from that fresh manifest instead of waiting for its TTL.
      ref.invalidate(nativeUpdateCheckProvider(false));
      ref.invalidate(nativeUpdateStateProvider);
      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      final (kind, message) = switch (result.status) {
        NativeUpdateCheckStatus.updateAvailable => (
          ToastKind.info,
          l10n.nativeUpdateAvailable(result.state.latestVersion),
        ),
        NativeUpdateCheckStatus.noUpdate => (
          ToastKind.success,
          l10n.nativeUpdateUpToDate,
        ),
        NativeUpdateCheckStatus.failed => (
          ToastKind.error,
          l10n.nativeUpdateCheckFailed,
        ),
        NativeUpdateCheckStatus.disabled ||
        NativeUpdateCheckStatus.unsupported => (
          ToastKind.info,
          l10n.nativeUpdateUnavailable,
        ),
      };
      AppMessenger.show(context, kind, message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
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
          const AppGroupedDivider(),
          InlineActionRow(
            icon: FLucideIcons.copy,
            label: l10n.settingsProductMetricsCopy,
            subtitle: l10n.settingsProductMetricsCopySubtitle,
            actionIcon: FLucideIcons.copy,
            onPress: () async {
              final report = ref
                  .read(productMetricsProvider.notifier)
                  .exportAggregates();
              await Clipboard.setData(ClipboardData(text: jsonEncode(report)));
              if (context.mounted) {
                AppMessenger.show(
                  context,
                  ToastKind.success,
                  l10n.settingsProductMetricsCopied,
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

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => AppPageScaffold(
    title: AppLocalizations.of(context).settingsAppearanceSection,
    childPad: false,
    child: ListView(
      children: const [
        AdaptiveContentFrame(
          maxWidth: AdaptiveMaxWidth.narrow,
          padding: EdgeInsets.all(AppSpacing.s16),
          primary: _Section(child: _AppearanceSection()),
        ),
      ],
    ),
  );
}
