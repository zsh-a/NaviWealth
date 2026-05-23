import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/config/app_version.dart';
import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../analytics/data/risk_threshold_preferences.dart';
import '../../auth/data/auth_controller.dart';
import '../../expense/data/expense_report_providers.dart';
import '../../fire/data/fire_plan_preferences.dart';
import '../../fire/domain/fire_plan.dart';
import '../../rebalance/data/rebalance_providers.dart';
import '../../rebalance/domain/allocation_schemes.dart';
import '../../rebalance/ui/target_allocation_editor_sheet.dart';
import '../../shared/forms/currency_picker.dart';
import '../data/base_currency_preference.dart';
import '../data/risk_appetite_preferences.dart';
import 'inline_setting_row.dart';

/// Settings landing page — iOS-style inset-grouped sections.
///
/// Every selector is a single-line [InlineSettingRow] (icon + label +
/// trailing value chip), giving the page roughly half the vertical
/// footprint of the legacy stacked `FSelect` layout while keeping every
/// option discoverable. Tap any row to open a dedicated picker sheet.
class SettingsOverview extends ConsumerWidget {
  const SettingsOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accountGroup = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: l10n.settingsAccountSection),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [_AccountSection()]),
        ),
      ],
    );
    const appearanceGroup = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppearanceSectionHeader(),
        SoftCard(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: _AppearanceSection(),
        ),
      ],
    );
    final riskGroup = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: l10n.settingsRiskSection),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              const _RiskAppetiteRow(),
              _SectionDivider(),
              _TargetAllocationLink(
                onTap: () => showTargetAllocationEditorSheet(context: context),
              ),
              _SectionDivider(),
              _MonthlyExpenseLink(
                onTap: () =>
                    context.goNamed(AppRouteNames.monthlyExpense),
              ),
              _SectionDivider(),
              _RiskThresholdsLink(
                onTap: () => context.goNamed(AppRouteNames.riskThresholds),
              ),
              _SectionDivider(),
              _StressTestLink(
                onTap: () => context.goNamed(AppRouteNames.stressTest),
              ),
            ],
          ),
        ),
      ],
    );
    final isLocalOnly = ref.watch(authControllerProvider).value is AuthLocalOnly;
    final dataGroup = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: l10n.settingsDataSection),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              if (!isLocalOnly) ...[
                InlineLinkRow(
                  icon: Icons.cloud_sync_outlined,
                  label: l10n.settingsSyncTitle,
                  subtitle: l10n.settingsSyncSubtitle,
                  onTap: () => context.goNamed(AppRouteNames.sync),
                ),
                _SectionDivider(),
              ],
              InlineLinkRow(
                icon: Icons.backup_outlined,
                label: l10n.settingsDataTitle,
                subtitle: l10n.settingsDataSubtitle,
                onTap: () => context.goNamed(AppRouteNames.backup),
              ),
              _SectionDivider(),
              InlineLinkRow(
                icon: Icons.lock_outline,
                label: l10n.settingsAiPrivacyTitle,
                subtitle: l10n.settingsAiPrivacySubtitle,
                onTap: () => context.goNamed(AppRouteNames.aiPrivacy),
              ),
              _SectionDivider(),
              InlineLinkRow(
                icon: Icons.visibility_outlined,
                label: l10n.settingsAiTransparencyTitle,
                subtitle: l10n.settingsAiTransparencySubtitle,
                onTap: () => context.goNamed(AppRouteNames.aiTransparency),
              ),
              _SectionDivider(),
              InlineLinkRow(
                icon: Icons.key_outlined,
                label: l10n.settingsAiLlmTitle,
                subtitle: l10n.settingsAiLlmSubtitle,
                onTap: () => context.goNamed(AppRouteNames.aiLlm),
              ),
            ],
          ),
        ),
      ],
    );
    final developerGroup = kDebugMode
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(title: l10n.settingsDeveloperSection),
              SoftCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: InlineLinkRow(
                  icon: Icons.bug_report_outlined,
                  label: l10n.settingsLogsTitle,
                  subtitle: l10n.settingsLogsSubtitle,
                  onTap: () => context.goNamed(AppRouteNames.logs),
                ),
              ),
            ],
          )
        : const SizedBox.shrink();
    const aboutGroup = SoftCard(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: _AboutTile(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        final basePadding = Breakpoints.isMobile(constraints.maxWidth)
            ? const EdgeInsets.all(16)
            : const EdgeInsets.all(24);
        final padding = basePadding.copyWith(
          bottom:
              basePadding.bottom + 64 + MediaQuery.paddingOf(context).bottom,
        );
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            AdaptiveContentFrame(
              maxWidth: isDesktop
                  ? AdaptiveMaxWidth.page
                  : AdaptiveMaxWidth.narrow,
              layout: isDesktop
                  ? AdaptiveFrameLayout.twoColumn
                  : AdaptiveFrameLayout.singleColumn,
              primaryFlex: 1,
              secondaryFlex: 1,
              padding: padding,
              header: const _AccountHeader(),
              primary: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  accountGroup,
                  const SizedBox(height: 16),
                  appearanceGroup,
                  if (!isDesktop) ...[
                    const SizedBox(height: 16),
                    riskGroup,
                    const SizedBox(height: 16),
                    dataGroup,
                    if (kDebugMode) ...[
                      const SizedBox(height: 16),
                      developerGroup,
                    ],
                    const SizedBox(height: 16),
                    aboutGroup,
                  ],
                ],
              ),
              secondary: isDesktop
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        riskGroup,
                        const SizedBox(height: 16),
                        dataGroup,
                        if (kDebugMode) ...[
                          const SizedBox(height: 16),
                          developerGroup,
                        ],
                        const SizedBox(height: 16),
                        aboutGroup,
                      ],
                    )
                  : null,
            ),
          ],
        );
      },
    );
  }
}

class _AppearanceSectionHeader extends StatelessWidget {
  const _AppearanceSectionHeader();

  @override
  Widget build(BuildContext context) {
    return _SectionHeader(
      title: AppLocalizations.of(context).settingsAppearanceSection,
    );
  }
}

/// iOS-style inset-grouped section header — small, all-caps, muted.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
      child: Text(
        title.toUpperCase(),
        style: context.theme.typography.xs2.copyWith(
          color: context.theme.colors.mutedForeground,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Single-pixel divider between adjacent rows in the same SoftCard
/// section. Matches the divider used elsewhere (alpha 0.05) so the
/// rows feel ribbon-grouped rather than card-stacked.
class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        height: 1,
        color: context.theme.colors.foreground.withValues(alpha: 0.05),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              // Soft teal disc — matches the icon affordance used in
              // SoftCard rows / AccountCategoryPicker so the avatar
              // reads as part of the same visual family rather than a
              // Material primaryContainer one-off.
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.account_circle_outlined,
              color: colors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsAccountTitle,
                  style: context.theme.typography.xl,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.settingsAccountSubtitle,
                  style: context.theme.typography.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);
    final isLocalOnly = ref.watch(authControllerProvider).value is AuthLocalOnly;

    return Column(
      children: [
        if (isLocalOnly)
          _LocalModeStatusRow(
            label: l10n.settingsAccountLocalOnlyBadge,
            subtitle: l10n.settingsAccountLocalOnlyHint,
          )
        else
          InlineLinkRow(
            icon: Icons.devices_outlined,
            label: l10n.settingsDevicesTitle,
            subtitle: l10n.settingsDevicesSubtitle,
            onTap: () => context.goNamed(AppRouteNames.devices),
          ),
        _SectionDivider(),
        InlineSettingRow<String>(
          icon: Icons.currency_exchange,
          label: l10n.settingsBaseCurrencyTitle,
          value: baseCurrency,
          options: {
            for (final code in kCommonCurrencies)
              currencyDisplayLabel(l10n, code): code,
          },
          onChanged: (picked) =>
              ref.read(baseCurrencyProvider.notifier).set(picked),
        ),
        _SectionDivider(),
        InlineLinkRow(
          icon: Icons.published_with_changes_outlined,
          label: l10n.settingsFxRatesTitle,
          subtitle: l10n.settingsFxRatesSubtitle,
          onTap: () => context.goNamed(AppRouteNames.fxRates),
        ),
      ],
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

    return Column(
      children: [
        InlineSettingRow<ThemeMode>(
          icon: Icons.brightness_6_outlined,
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
        _SectionDivider(),
        InlineSettingRow<MarketColorMode>(
          icon: Icons.swap_vert,
          label: l10n.settingsMarketColorTitle,
          value: marketMode,
          options: {
            for (final m in MarketColorMode.values)
              _marketModeLabel(l10n, m): m,
          },
          onChanged: (m) => ref.read(marketColorModeProvider.notifier).set(m),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: _MarketColorPreview(),
        ),
        _SectionDivider(),
        InlineSettingRow<String>(
          icon: Icons.translate_outlined,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.mutedForeground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.settingsAboutTitle,
                  style: context.theme.typography.sm,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.theme.typography.xs.copyWith(
                    color: colors.mutedForeground,
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

class _MarketColorPreview extends StatelessWidget {
  const _MarketColorPreview();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        DeltaChip(value: 1.23, format: DeltaFormat.percent),
        DeltaChip(value: -0.42, format: DeltaFormat.percent),
        DeltaChip(value: 0, format: DeltaFormat.percent),
      ],
    );
  }
}

/// Risk appetite chip row — the single user-facing dial that drives
/// rebalance preset, AI tone and (by default) concentration alert
/// sensitivity. Sits at the top of the Investment Preferences card so
/// it reads as the section's "main idea".
class _RiskAppetiteRow extends ConsumerWidget {
  const _RiskAppetiteRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final appetite = ref.watch(riskAppetiteProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_outlined,
                size: 18,
                color: colors.mutedForeground,
              ),
              const SizedBox(width: 12),
              Text(
                l10n.settingsRiskAppetiteLabel,
                style: context.theme.typography.sm,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // The row is intentionally tight — chips share a stadium
          // shape and the active one paints in the AI active tone, so
          // selection is glanceable without verbose copy.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in _appetiteOptionsForChips(l10n))
                AiPill(
                  label: option.label,
                  state: appetite == option.value
                      ? AiPillState.selected
                      : AiPillState.neutral,
                  onTap: () => _onPick(ref, option.value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onPick(WidgetRef ref, RiskAppetite next) async {
    final current = ref.read(riskAppetiteProvider);
    if (current == next) return;
    // Capture the thresholds *before* writing the appetite, so a
    // hand-customised state ("not at any preset") is preserved.
    final priorThresholds = ref.read(concentrationThresholdsProvider);
    await ref.read(riskAppetiteProvider.notifier).set(next);
    // Picking a non-custom preset resets target weights to that
    // preset's defaults. Custom is reached via the target editor
    // sheet itself (which writes appetite = custom internally).
    if (next != RiskAppetite.custom) {
      await ref
          .read(targetAllocationProvider.notifier)
          .update(allocationScheme(schemePresetFor(next)));
    }
    // Honour the "auto-tuned by your risk appetite" promise on the
    // thresholds link row: when the user hasn't drifted off the
    // appetite-aligned presets, snap the thresholds to match the new
    // appetite. Hand-customised thresholds (not at any preset) stay
    // put — those users explicitly opted out of the auto-tune.
    if (isAtAnyAppetitePreset(priorThresholds)) {
      await ref
          .read(concentrationThresholdsProvider.notifier)
          .applyAll(concentrationThresholdsForAppetite(next));
    }
  }
}

class _AppetiteOption {
  const _AppetiteOption(this.value, this.label);
  final RiskAppetite value;
  final String label;
}

List<_AppetiteOption> _appetiteOptionsForChips(AppLocalizations l10n) {
  return [
    _AppetiteOption(
      RiskAppetite.conservative,
      l10n.settingsRiskAppetiteConservative,
    ),
    _AppetiteOption(RiskAppetite.moderate, l10n.settingsRiskAppetiteModerate),
    _AppetiteOption(
      RiskAppetite.aggressive,
      l10n.settingsRiskAppetiteAggressive,
    ),
    _AppetiteOption(RiskAppetite.custom, l10n.settingsRiskAppetiteCustom),
  ];
}

class _TargetAllocationLink extends ConsumerWidget {
  const _TargetAllocationLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appetite = ref.watch(riskAppetiteProvider);
    final subtitle = appetite == RiskAppetite.custom
        ? l10n.settingsTargetAllocationSubtitleCustom
        : l10n.settingsTargetAllocationSubtitlePreset(
            switch (appetite) {
              RiskAppetite.conservative => l10n.settingsRiskAppetiteConservative,
              RiskAppetite.moderate => l10n.settingsRiskAppetiteModerate,
              RiskAppetite.aggressive => l10n.settingsRiskAppetiteAggressive,
              RiskAppetite.custom => l10n.settingsRiskAppetiteCustom,
            },
          );
    return InlineLinkRow(
      icon: Icons.donut_small_outlined,
      label: l10n.settingsTargetAllocationLabel,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

class _RiskThresholdsLink extends ConsumerWidget {
  const _RiskThresholdsLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final thresholds = ref.watch(concentrationThresholdsProvider);
    // "Custom" iff the user has drifted off every appetite-aligned
    // preset. Just being non-default no longer counts: aggressive
    // users sitting on the aggressive preset are still "auto-tuned".
    final isCustom = !isAtAnyAppetitePreset(thresholds);
    return InlineLinkRow(
      icon: Icons.notifications_active_outlined,
      label: l10n.settingsRiskThresholdsLabel,
      subtitle: isCustom
          ? l10n.settingsRiskThresholdsSubtitleCustom
          : l10n.settingsRiskThresholdsSubtitleAuto,
      onTap: onTap,
    );
  }
}

class _StressTestLink extends ConsumerWidget {
  const _StressTestLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final risk = ref.watch(firePlanExtrasProvider).riskSettings;
    final isCustom = risk != const FireRiskSettings();
    return InlineLinkRow(
      icon: Icons.science_outlined,
      label: l10n.settingsStressTestLabel,
      subtitle: isCustom
          ? l10n.settingsStressTestSubtitleCustom
          : l10n.settingsStressTestSubtitleAuto,
      onTap: onTap,
    );
  }
}

class _MonthlyExpenseLink extends ConsumerWidget {
  const _MonthlyExpenseLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(monthlyExpensePreferencesProvider);
    final subtitle = prefs.override != null
        ? l10n.settingsMonthlyExpenseSubtitleOverride
        : l10n.settingsMonthlyExpenseSubtitleAuto(prefs.windowMonths);
    return InlineLinkRow(
      icon: Icons.calendar_view_month_outlined,
      label: l10n.settingsMonthlyExpenseLabel,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

/// Non-tappable status row shown in place of the Devices link for
/// local-only users. Mirrors [InlineLinkRow]'s layout sans chevron.
class _LocalModeStatusRow extends StatelessWidget {
  const _LocalModeStatusRow({required this.label, required this.subtitle});

  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.smartphone_outlined,
            size: 18,
            color: colors.mutedForeground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: context.theme.typography.sm),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    style: context.theme.typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
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
