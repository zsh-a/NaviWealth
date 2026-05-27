import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth_providers;
import '../../../core/config/app_version.dart';
import '../../../core/haptics/haptics.dart';
import '../../../core/logging/crash_reporting_preference.dart';
import '../../../core/notifications/providers.dart' as notif_providers;
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../analytics/data/risk_threshold_preferences.dart';
import '../../auth/data/auth_controller.dart';
import '../../expense/data/expense_report_providers.dart';
import '../../fire/data/fire_plan_preferences.dart';
import '../../fire/domain/fire_plan.dart';
import '../../health/agents/providers.dart' as health_agent_providers;
import '../../health/data/health_sync_service.dart';
import '../../health/data/morning_briefing_preferences.dart';
import '../../health/data/providers.dart' as health_data;
import '../../rebalance/data/rebalance_providers.dart';
import '../../rebalance/domain/allocation_schemes.dart';
import '../../rebalance/ui/target_allocation_editor_sheet.dart';
import '../../shared/forms/currency_picker.dart';
import '../data/base_currency_preference.dart';
import '../data/risk_appetite_preferences.dart';
import 'inline_setting_row.dart';

/// Settings landing page — iOS-style inset-grouped sections.
///
/// Section order maps to user mental model (most-personal → least):
///
///   1. Account            cloud / device identity
///   2. Numbers & Money    base currency, FX rates — formatting + financial semantics
///   3. Appearance         theme / market color / language
///   4. Planning           Plan-tab parameters (risk appetite, allocation, expense, thresholds, stress)
///   5. AI                 privacy → LLM provider → transparency
///   6. Data               sync + backup
///   7. About              version / commit
///   8. Developer          debug-only escape hatches
///
/// The previous `_AccountHeader` decorative tile is gone — the page
/// title comes from `appSubPageHeader` in `settings_page.dart`, so the
/// section list starts at the top with no redundant chrome.
class SettingsOverview extends ConsumerWidget {
  const SettingsOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    final accountGroup = _Section(
      title: l10n.settingsAccountSection,
      child: _AccountSection(),
    );
    final numbersGroup = _Section(
      title: l10n.settingsNumbersAndMoneySection,
      child: _NumbersAndMoneySection(),
    );
    const appearanceGroup = _Section(
      titleKey: _SectionTitleKey.appearance,
      child: _AppearanceSection(),
    );
    final planningGroup = _Section(
      title: l10n.settingsPlanningSection,
      child: Column(
        children: [
          const _RiskAppetiteRow(),
          _SectionDivider(),
          _TargetAllocationLink(
            onTap: () => showTargetAllocationEditorSheet(context: context),
          ),
          _SectionDivider(),
          _MonthlyExpenseLink(
            onTap: () => context.goNamed(AppRouteNames.monthlyExpense),
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
    );
    final aiGroup = _Section(
      title: l10n.settingsAiSection,
      child: Column(
        children: [
          InlineLinkRow(
            icon: FLucideIcons.lock,
            label: l10n.settingsAiPrivacyTitle,
            subtitle: l10n.settingsAiPrivacySubtitle,
            onTap: () => context.goNamed(AppRouteNames.aiPrivacy),
          ),
          _SectionDivider(),
          InlineLinkRow(
            icon: FLucideIcons.key,
            label: l10n.settingsAiLlmTitle,
            subtitle: l10n.settingsAiLlmSubtitle,
            onTap: () => context.goNamed(AppRouteNames.aiLlm),
          ),
          _SectionDivider(),
          InlineLinkRow(
            icon: FLucideIcons.eye,
            label: l10n.settingsAiTransparencyTitle,
            subtitle: l10n.settingsAiTransparencySubtitle,
            onTap: () => context.goNamed(AppRouteNames.aiTransparency),
          ),
          _SectionDivider(),
          InlineLinkRow(
            icon: FLucideIcons.download,
            label: 'AI 模型',
            subtitle: '下载 / 管理本地 embedder 模型 (EmbeddingGemma)',
            onTap: () => context.goNamed(AppRouteNames.aiModels),
          ),
        ],
      ),
    );
    final isLocalOnly =
        ref.watch(authControllerProvider).value is AuthLocalOnly;
    final dataGroup = _Section(
      title: l10n.settingsDataSection,
      child: Column(
        children: [
          if (!isLocalOnly) ...[
            InlineLinkRow(
              icon: FLucideIcons.refreshCw,
              label: l10n.settingsSyncTitle,
              subtitle: l10n.settingsSyncSubtitle,
              onTap: () => context.goNamed(AppRouteNames.sync),
            ),
            _SectionDivider(),
          ],
          InlineLinkRow(
            icon: FLucideIcons.cloudUpload,
            label: l10n.settingsDataTitle,
            subtitle: l10n.settingsDataSubtitle,
            onTap: () => context.goNamed(AppRouteNames.backup),
          ),
          _SectionDivider(),
          const _CrashReportingRow(),
        ],
      ),
    );
    // D-1.5: per-user LifeOS domain opt-in. FinanceOS is always-on; future
    // domains (HealthOS in D-2 onward) ship behind an explicit toggle so a
    // new domain landing in the binary doesn't activate without consent.
    const domainsGroup = _Section(
      title: 'LifeOS 域',
      child: _DomainsSection(),
    );
    final aboutGroup = _Section(
      title: l10n.settingsAboutSection,
      child: const _AboutTile(),
    );
    final developerGroup = kDebugMode
        ? _Section(
            title: l10n.settingsDeveloperSection,
            child: InlineLinkRow(
              icon: FLucideIcons.bug,
              label: l10n.settingsLogsTitle,
              subtitle: l10n.settingsLogsSubtitle,
              onTap: () => context.goNamed(AppRouteNames.logs),
            ),
          )
        : const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two-column at ≥ 760dp instead of 1024dp — settings is
        // list-heavy and benefits from horizontal density on phones in
        // landscape, foldables, and small tablets.
        final isWide = constraints.maxWidth >= 760;
        final basePadding = Breakpoints.isMobile(constraints.maxWidth)
            ? const EdgeInsets.all(16)
            : const EdgeInsets.all(24);
        final padding = basePadding.copyWith(
          bottom:
              basePadding.bottom + 64 + MediaQuery.paddingOf(context).bottom,
        );

        final allGroupsSingleColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            accountGroup,
            const SizedBox(height: 16),
            numbersGroup,
            const SizedBox(height: 16),
            appearanceGroup,
            const SizedBox(height: 16),
            planningGroup,
            const SizedBox(height: 16),
            aiGroup,
            const SizedBox(height: 16),
            dataGroup,
            const SizedBox(height: 16),
            domainsGroup,
            const SizedBox(height: 16),
            aboutGroup,
            if (kDebugMode) ...[const SizedBox(height: 16), developerGroup],
          ],
        );

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            AdaptiveContentFrame(
              maxWidth: isWide
                  ? AdaptiveMaxWidth.page
                  : AdaptiveMaxWidth.narrow,
              layout: isWide
                  ? AdaptiveFrameLayout.twoColumn
                  : AdaptiveFrameLayout.singleColumn,
              primaryFlex: 1,
              secondaryFlex: 1,
              padding: padding,
              primary: isWide
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        accountGroup,
                        const SizedBox(height: 16),
                        numbersGroup,
                        const SizedBox(height: 16),
                        appearanceGroup,
                        const SizedBox(height: 16),
                        planningGroup,
                      ],
                    )
                  : allGroupsSingleColumn,
              secondary: isWide
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        aiGroup,
                        const SizedBox(height: 16),
                        dataGroup,
                        const SizedBox(height: 16),
                        domainsGroup,
                        const SizedBox(height: 16),
                        aboutGroup,
                        if (kDebugMode) ...[
                          const SizedBox(height: 16),
                          developerGroup,
                        ],
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

/// Section title lookup for one historical key that lived under a
/// dedicated widget. Most sections now pass `title:` directly.
enum _SectionTitleKey { appearance }

class _Section extends StatelessWidget {
  const _Section({this.title, this.titleKey, required this.child})
    : assert(
        title != null || titleKey != null,
        'A section needs either a literal title or a titleKey',
      );

  final String? title;
  final _SectionTitleKey? titleKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final resolvedTitle = title ?? _resolveTitleKey(context, titleKey!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: resolvedTitle),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: child,
        ),
      ],
    );
  }

  static String _resolveTitleKey(BuildContext context, _SectionTitleKey key) {
    final l10n = AppLocalizations.of(context);
    return switch (key) {
      _SectionTitleKey.appearance => l10n.settingsAppearanceSection,
    };
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

class _AccountSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isLocalOnly =
        ref.watch(authControllerProvider).value is AuthLocalOnly;

    if (isLocalOnly) {
      return _LocalModeStatusRow(
        label: l10n.settingsAccountLocalOnlyBadge,
        subtitle: l10n.settingsAccountLocalOnlyHint,
      );
    }
    return InlineLinkRow(
      icon: FLucideIcons.monitor,
      label: l10n.settingsDevicesTitle,
      subtitle: l10n.settingsDevicesSubtitle,
      onTap: () => context.goNamed(AppRouteNames.devices),
    );
  }
}

class _NumbersAndMoneySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);

    return Column(
      children: [
        InlineSettingRow<String>(
          icon: FLucideIcons.arrowLeftRight,
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
          icon: FLucideIcons.refreshCw,
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
        _SectionDivider(),
        InlineSettingRow<MarketColorMode>(
          icon: FLucideIcons.arrowUpDown,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(FLucideIcons.info, size: 18, color: colors.mutedForeground),
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
/// Opt-in toggle for anonymous crash + breadcrumb telemetry
/// (`roadmap-next.md` §3.6). Defaults to OFF — flipping this only takes
/// effect on the *next* error captured, not retroactively, and even when
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

/// rebalance preset, AI tone and (by default) concentration alert
/// sensitivity. Sits at the top of the Planning card so it reads as
/// the section's "main idea".
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
                FLucideIcons.slidersHorizontal,
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
    // Subtitle now carries the *preset name* (not the wordy "auto-tuned by
    // your aggressive appetite" sentence) — the AUTO badge on the right
    // already conveys the auto-tune state.
    final subtitle = switch (appetite) {
      RiskAppetite.conservative => l10n.settingsRiskAppetiteConservative,
      RiskAppetite.moderate => l10n.settingsRiskAppetiteModerate,
      RiskAppetite.aggressive => l10n.settingsRiskAppetiteAggressive,
      RiskAppetite.custom => l10n.settingsRiskAppetiteCustom,
    };
    return InlineLinkRow(
      icon: FLucideIcons.chartPie,
      label: l10n.settingsTargetAllocationLabel,
      subtitle: subtitle,
      trailingBadge: appetite == RiskAppetite.custom
          ? l10n.settingsBadgeCustom
          : l10n.settingsBadgeAuto,
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
      icon: FLucideIcons.bellRing,
      label: l10n.settingsRiskThresholdsLabel,
      trailingBadge: isCustom
          ? l10n.settingsBadgeCustom
          : l10n.settingsBadgeAuto,
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
      icon: FLucideIcons.flaskConical,
      label: l10n.settingsStressTestLabel,
      trailingBadge: isCustom
          ? l10n.settingsBadgeCustom
          : l10n.settingsBadgeAuto,
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
    final isOverride = prefs.override != null;
    final subtitle = isOverride
        ? l10n.settingsMonthlyExpenseSubtitleOverride
        : l10n.settingsMonthlyExpenseSubtitleAuto(prefs.windowMonths);
    return InlineLinkRow(
      icon: FLucideIcons.calendarDays,
      label: l10n.settingsMonthlyExpenseLabel,
      subtitle: subtitle,
      trailingBadge: isOverride
          ? l10n.settingsBadgeCustom
          : l10n.settingsBadgeAuto,
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
            FLucideIcons.smartphone,
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

/// D-1.5 — LifeOS per-user domain opt-in section.
///
/// FinanceOS is the seed domain so its row reads as read-only "已启用".
/// HealthOS is wired but the toggle is disabled until D-2 ships; the
/// subtitle communicates that state instead of pretending the feature is
/// ready. Once `features/health/` exists the disabled clause goes away.
class _DomainsSection extends ConsumerWidget {
  const _DomainsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optIns = ref
        .watch(auth_providers.domainOptInsProvider)
        .value;

    final healthEnabled =
        optIns?.contains(DomainScope.health) ?? false;

    return Column(
      children: [
        InlineLinkRow(
          icon: FLucideIcons.wallet,
          label: 'FinanceOS',
          subtitle: '永远启用 (seed 域)',
          trailingBadge: '已启用',
          onTap: () {},
        ),
        _SectionDivider(),
        InlineSwitchRow(
          icon: FLucideIcons.heartPulse,
          label: 'HealthOS',
          // D-2.3 (2026-05-27): AI tools + Memory Layer indexer + IA
          // shell spec all live. Real Today/Trend/Plan pages land in
          // D-2.2 once the HealthKit / Health Connect adapter is in;
          // the toggle gates the AI tool list + memory indexing today.
          subtitle: healthEnabled
              ? '预览中 — AI 工具 + Memory 索引已启用 (Today/Trend/Plan 页面 D-2.2 落地)'
              : '预览版 — 打开后 AI 工具 + Memory 索引会启用',
          value: healthEnabled,
          onChanged: (v) {
            ref
                .read(auth_providers.domainOptInsProvider.notifier)
                .setEnabled(DomainScope.health, v);
          },
        ),
        if (healthEnabled) ...[
          _SectionDivider(),
          InlineLinkRow(
            icon: FLucideIcons.eye,
            label: 'HealthOS · Today',
            subtitle: '查看每日 Morning Briefing 卡片',
            onTap: () => context.goNamed(AppRouteNames.healthToday),
          ),
          _SectionDivider(),
          const _HealthPlatformSyncRow(),
          _SectionDivider(),
          const _MorningBriefingRunRow(),
          _SectionDivider(),
          const _MorningBriefingHourRow(),
        ],
      ],
    );
  }
}

/// D-2.2 — manual "Sync from HealthKit / Health Connect" trigger.
///
/// Shown only when HealthOS is opt-in. Tapping requests permissions on
/// first use, then pulls the last 30 days into `health_metrics`.
/// Background fetch / WorkManager scheduling lands in D-2.5b; this is
/// the dogfood path until then.
class _HealthPlatformSyncRow extends ConsumerStatefulWidget {
  const _HealthPlatformSyncRow();

  @override
  ConsumerState<_HealthPlatformSyncRow> createState() =>
      _HealthPlatformSyncRowState();
}

class _HealthPlatformSyncRowState
    extends ConsumerState<_HealthPlatformSyncRow> {
  bool _running = false;
  HealthSyncResult? _lastResult;

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final service = await ref.read(
        health_data.healthSyncServiceProvider.future,
      );
      // Permissions are a precondition — request them if missing so the
      // user doesn't have to remember to do a separate "Connect" step.
      if (!await service.hasPermissions()) {
        final granted = await service.requestPermissions();
        if (!granted) {
          setState(() {
            _lastResult = HealthSyncResult.skipped(
              startedAt: DateTime.now().toUtc(),
              errorMessage: '权限被拒绝 — 在系统 Health 设置里再试',
            );
          });
          return;
        }
      }
      final result = await service.syncRange();
      setState(() => _lastResult = result);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _subtitle() {
    final r = _lastResult;
    if (_running) return '正在拉取…';
    if (r == null) return '从 HealthKit / Health Connect 拉取最近 30 天数据';
    if (!r.ok) return r.errorMessage ?? '上次同步失败';
    return '上次同步: ${r.upserted} 新写入 / ${r.unchanged} 未变 · 拉取 ${r.totalFetched} 项';
  }

  @override
  Widget build(BuildContext context) {
    return InlineLinkRow(
      icon: FLucideIcons.refreshCcw,
      label: 'Sync from HealthKit / Health Connect',
      subtitle: _subtitle(),
      onTap: _running ? () {} : _run,
    );
  }
}

/// D-2.5b — manual "Run morning briefing now" trigger + notification
/// permission status.
///
/// The user usually doesn't need to tap this — the workmanager
/// background task fires the agent daily and posts a local
/// notification. The button exists for dogfood + first-run flows
/// (initial permission grant, "did it work?" sanity check).
class _MorningBriefingRunRow extends ConsumerStatefulWidget {
  const _MorningBriefingRunRow();

  @override
  ConsumerState<_MorningBriefingRunRow> createState() =>
      _MorningBriefingRunRowState();
}

class _MorningBriefingRunRowState
    extends ConsumerState<_MorningBriefingRunRow> {
  bool _running = false;
  AgentRunResult? _lastResult;
  String? _errorMessage;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _errorMessage = null;
    });
    try {
      // First-time runs need notification permission so the toast
      // ever actually reaches the user; request it before kicking off
      // the agent so the prompt and the run are paired.
      final notifier = ref.read(notif_providers.notificationServiceProvider);
      if (await notifier.isAvailable() && !await notifier.hasPermissions()) {
        await notifier.requestPermissions();
      }
      // `refresh` re-runs the autoDispose provider even if it was
      // already in the cache from an earlier invocation. We await the
      // future directly so the result lands in our local state.
      final result = await ref.refresh(
        health_agent_providers.manualMorningBriefingRunProvider.future,
      );
      setState(() => _lastResult = result);
    } on Object catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _subtitle() {
    if (_running) return '正在运行 Morning Briefing…';
    final err = _errorMessage;
    if (err != null) return 'Briefing failed: $err';
    final r = _lastResult;
    if (r == null) {
      return '后台每日 07:00 自动跑;点这里手动触发并发通知';
    }
    return switch (r.status) {
      AgentRunStatus.completed => 'Last run: ${r.summary ?? "completed"}',
      AgentRunStatus.skipped => 'Last run skipped: ${r.summary ?? "no signal"}',
      AgentRunStatus.failed => 'Last run failed: ${r.error ?? "unknown"}',
    };
  }

  @override
  Widget build(BuildContext context) {
    return InlineLinkRow(
      icon: FLucideIcons.sunrise,
      label: 'Run Morning Briefing now',
      subtitle: _subtitle(),
      onTap: _running ? () {} : _run,
    );
  }
}

/// D-2.5b follow-up — user-configurable preferred local hour for the
/// daily briefing. Defaults to 07:00. Background workmanager fires at
/// OS discretion (≈24h period) so the hour is honoured strictly only
/// by in-process scheduling; the value is still surfaced through the
/// `AgentSchedule` so the briefing's documented intent matches the
/// user's preference.
class _MorningBriefingHourRow extends ConsumerWidget {
  const _MorningBriefingHourRow();

  Future<void> _pick(BuildContext context, WidgetRef ref, int current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current, minute: 0),
      helpText: 'Morning Briefing 时间',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    await ref.read(morningBriefingHourProvider.notifier).set(picked.hour);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hour = ref.watch(morningBriefingHourProvider);
    final label = hour.toString().padLeft(2, '0');
    return InlineLinkRow(
      icon: FLucideIcons.clock,
      label: 'Briefing 时间',
      subtitle: '每日大约 $label:00 触发 (后台调度窗口浮动)',
      trailingValue: '$label:00',
      onTap: () => _pick(context, ref, hour),
    );
  }
}

