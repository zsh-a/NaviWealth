import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/config/app_version.dart';
import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../analytics/data/risk_threshold_preferences.dart';
import '../../shared/forms/currency_picker.dart';
import '../data/base_currency_preference.dart';

class SettingsOverview extends ConsumerWidget {
  const SettingsOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return ListView(
      padding: Spacing.pageMobile.copyWith(
        bottom:
            Spacing.pageMobile.bottom +
            Spacing.floatingBarClearance +
            MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const _AccountHeader(),
        const SizedBox(height: Spacing.s12),
        const _AccountSection(),
        _SectionHeader(title: l10n.settingsAppearanceSection),
        const _AppearanceSection(),
        _SectionHeader(title: l10n.settingsRiskSection),
        const FCard.raw(child: _RiskThresholdSettings()),
        _SectionHeader(title: l10n.settingsDataSection),
        FCard.raw(
          child: Column(
            children: [
              FTile(
                title: Text(l10n.settingsSyncTitle),
                prefix: const Icon(Icons.cloud_sync_outlined),
                subtitle: Text(l10n.settingsSyncSubtitle),
                suffix: const Icon(Icons.chevron_right),
                onPress: () => context.goNamed(AppRouteNames.sync),
              ),
              const FDivider(),
              FTile(
                title: Text(l10n.settingsDataTitle),
                prefix: const Icon(Icons.backup_outlined),
                subtitle: Text(l10n.settingsDataSubtitle),
                suffix: const Icon(Icons.chevron_right),
                onPress: () => context.goNamed(AppRouteNames.backup),
              ),
            ],
          ),
        ),
        if (kDebugMode) ...[
          _SectionHeader(title: l10n.settingsDeveloperSection),
          FCard.raw(
            child: FTile(
              title: Text(l10n.settingsLogsTitle),
              prefix: const Icon(Icons.bug_report_outlined),
              subtitle: Text(l10n.settingsLogsSubtitle),
              suffix: const Icon(Icons.chevron_right),
              onPress: () => context.goNamed(AppRouteNames.logs),
            ),
          ),
        ],
        const SizedBox(height: Spacing.s12),
        const FCard.raw(child: _AboutTile()),
      ],
    );
  }
}

/// Light section header — Apple-News style accent title above each card group.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        title,
        style: TypographyTokens.sectionHeaderTitle(scheme.primary),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.s8),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: Radii.brLg,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.account_circle_outlined,
              color: scheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: Spacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsAccountTitle,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: Spacing.s2),
                Text(
                  l10n.settingsAccountSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);

    return FCard.raw(
      child: Column(
        children: [
          FTile(
            title: Text(l10n.settingsDevicesTitle),
            prefix: const Icon(Icons.devices_outlined),
            subtitle: Text(l10n.settingsDevicesSubtitle),
            suffix: const Icon(Icons.chevron_right),
            onPress: () => context.goNamed(AppRouteNames.devices),
          ),
          const FDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.s16,
              vertical: Spacing.s8,
            ),
            child: Row(
              children: [
                const Icon(Icons.currency_exchange),
                const SizedBox(width: Spacing.s16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: baseCurrency,
                    decoration: InputDecoration(
                      labelText: l10n.settingsBaseCurrencyTitle,
                    ),
                    items: [
                      for (final code in kCommonCurrencies)
                        DropdownMenuItem(
                          value: code,
                          child: Text(currencyDisplayLabel(l10n, code)),
                        ),
                    ],
                    selectedItemBuilder: (context) => [
                      for (final code in kCommonCurrencies)
                        Text(
                          code,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                    ],
                    onChanged: (picked) async {
                      if (picked != null && picked != baseCurrency) {
                        await ref
                            .read(baseCurrencyProvider.notifier)
                            .set(picked);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const FDivider(),
          FTile(
            title: Text(l10n.settingsFxRatesTitle),
            prefix: const Icon(Icons.published_with_changes_outlined),
            subtitle: Text(l10n.settingsFxRatesSubtitle),
            suffix: const Icon(Icons.chevron_right),
            onPress: () => context.goNamed(AppRouteNames.fxRates),
          ),
        ],
      ),
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final marketMode = ref.watch(marketColorModeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return FCard.raw(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.s16,
              vertical: Spacing.s8,
            ),
            child: Row(
              children: [
                const Icon(Icons.brightness_6_outlined),
                const SizedBox(width: Spacing.s16),
                Expanded(
                  child: DropdownButtonFormField<ThemeMode>(
                    isExpanded: true,
                    initialValue: themeMode,
                    decoration: InputDecoration(
                      labelText: l10n.settingsThemeModeTitle,
                    ),
                    items: [
                      for (final m in ThemeMode.values)
                        DropdownMenuItem(
                          value: m,
                          child: Text(_themeModeLabel(l10n, m)),
                        ),
                    ],
                    onChanged: (m) {
                      if (m != null) {
                        Haptics.selection();
                        ref.read(themeModeProvider.notifier).set(m);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const FDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.s16,
              vertical: Spacing.s8,
            ),
            child: Row(
              children: [
                const Icon(Icons.swap_vert),
                const SizedBox(width: Spacing.s16),
                Expanded(
                  child: DropdownButtonFormField<MarketColorMode>(
                    isExpanded: true,
                    initialValue: marketMode,
                    decoration: InputDecoration(
                      labelText: l10n.settingsMarketColorTitle,
                    ),
                    items: [
                      for (final m in MarketColorMode.values)
                        DropdownMenuItem(
                          value: m,
                          child: Text(_marketModeLabel(l10n, m)),
                        ),
                    ],
                    onChanged: (m) {
                      if (m != null) {
                        ref.read(marketColorModeProvider.notifier).set(m);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _MarketColorPreview(),
          ),
          const FDivider(),
          const _CompactDensityTile(),
          const FDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.s16,
              vertical: Spacing.s8,
            ),
            child: Row(
              children: [
                const Icon(Icons.translate_outlined),
                const SizedBox(width: Spacing.s16),
                Expanded(
                  child: DropdownButtonFormField<Locale?>(
                    isExpanded: true,
                    initialValue: locale,
                    decoration: InputDecoration(
                      labelText: l10n.settingsLanguageTitle,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(l10n.langSystem),
                      ),
                      DropdownMenuItem(
                        value: const Locale('en'),
                        child: Text(l10n.langEnglish),
                      ),
                      DropdownMenuItem(
                        value: const Locale('zh'),
                        child: Text(l10n.langChinese),
                      ),
                    ],
                    onChanged: (picked) {
                      Haptics.selection();
                      ref.read(localeProvider.notifier).set(picked);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    return FTile(
      title: Text(l10n.settingsAboutTitle),
      prefix: const Icon(Icons.info_outline),
      subtitle: Text(subtitle),
    );
  }
}

class _CompactDensityTile extends ConsumerWidget {
  const _CompactDensityTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final compact = ref.watch(compactDensityProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s16,
        vertical: Spacing.s8,
      ),
      child: Row(
        children: [
          const Icon(Icons.density_medium_outlined),
          const SizedBox(width: Spacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsCompactDensityTitle),
                Text(
                  l10n.settingsCompactDensitySubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          FSwitch(
            value: compact,
            onChange: (next) {
              Haptics.selection();
              ref.read(compactDensityProvider.notifier).set(next);
            },
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
      spacing: Spacing.s8,
      runSpacing: Spacing.s8,
      children: [
        DeltaChip(value: 1.23, format: DeltaFormat.percent),
        DeltaChip(value: -0.42, format: DeltaFormat.percent),
        DeltaChip(value: 0, format: DeltaFormat.percent),
      ],
    );
  }
}

class _RiskThresholdSettings extends ConsumerWidget {
  const _RiskThresholdSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final thresholds = ref.watch(concentrationThresholdsProvider);

    return Column(
      children: [
        _ThresholdSlider(
          icon: Icons.account_balance_wallet_outlined,
          label: l10n.settingsRiskAssetLabel,
          subtitle: l10n.settingsRiskAssetSubtitle,
          value: thresholds.assetWarning,
          onChanged: (v) =>
              ref.read(concentrationThresholdsProvider.notifier).updateAsset(v),
        ),
        _ThresholdSlider(
          icon: Icons.category_outlined,
          label: l10n.settingsRiskSectorLabel,
          subtitle: l10n.settingsRiskSectorSubtitle,
          value: thresholds.sectorWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateSector(v),
        ),
        _ThresholdSlider(
          icon: Icons.public,
          label: l10n.settingsRiskRegionLabel,
          subtitle: l10n.settingsRiskRegionSubtitle,
          value: thresholds.regionWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateRegion(v),
        ),
        _ThresholdSlider(
          icon: Icons.currency_exchange,
          label: l10n.settingsRiskCurrencyLabel,
          subtitle: l10n.settingsRiskCurrencySubtitle,
          value: thresholds.currencyWarning,
          onChanged: (v) => ref
              .read(concentrationThresholdsProvider.notifier)
              .updateCurrency(v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FButton(
              onPress: () => ref
                  .read(concentrationThresholdsProvider.notifier)
                  .resetToDefaults(),
              variant: FButtonVariant.ghost,
              child: Text(l10n.settingsRiskResetDefaults),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FTile(
      title: Text(label),
      prefix: Icon(icon),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          Row(
            children: [
              Expanded(
                child: FSlider(
                  control: FSliderControl.managedContinuous(
                    initial: FSliderValue(max: (value - 0.05) / 0.90),
                    onChange: (v) => onChanged(0.05 + v.max * 0.90),
                  ),
                  tooltipBuilder: (_, v) =>
                      Text('${((0.05 + v * 0.90) * 100).round()}%'),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(value * 100).round()}%',
                  style: theme.textTheme.titleSmall,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
