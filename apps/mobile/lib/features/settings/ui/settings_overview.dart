import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/config/app_version.dart';
import '../../../core/haptics/haptics.dart';
import '../../../core/logging/crash_reporting_preference.dart';
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
            label: l10n.settingsAiModelsTitle,
            subtitle: l10n.settingsAiModelsSubtitle,
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
    // D-1.5: per-user LifeOS domain opt-in lives on its own focused page
    // (`/settings/domains`) so the overview doesn't grow/shrink as domains
    // toggle and per-domain ops (HealthOS sync / briefing) aren't crammed
    // into the global preferences list. The overview just links in.
    final domainsGroup = _Section(
      title: l10n.settingsDomainsSection,
      child: InlineLinkRow(
        icon: FLucideIcons.layoutGrid,
        label: l10n.settingsDomainsTitle,
        subtitle: l10n.settingsDomainsSubtitle,
        onTap: () => context.goNamed(AppRouteNames.domains),
      ),
    );
    final aboutGroup = _Section(
      title: l10n.settingsAboutSection,
      child: const _AboutTile(),
    );
    // Logs viewer is exposed in release as well — the talker history is
    // already kept in memory in every build, and dogfood users need a
    // way to copy diagnostics out (e.g. Health Connect permission flow)
    // without a debug attach.
    final advancedGroup = _Section(
      title: l10n.settingsAdvancedSection,
      child: Column(
        children: [
          InlineLinkRow(
            icon: FLucideIcons.bug,
            label: l10n.settingsLogsTitle,
            subtitle: l10n.settingsLogsSubtitle,
            onTap: () => context.goNamed(AppRouteNames.logs),
          ),
          _SectionDivider(),
          InlineLinkRow(
            icon: FLucideIcons.activity,
            label: l10n.settingsPerfTitle,
            subtitle: l10n.settingsPerfSubtitle,
            onTap: () => context.goNamed(AppRouteNames.performance),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two-column at ≥ 760dp instead of 1024dp — settings is
        // list-heavy and benefits from horizontal density on phones in
        // landscape, foldables, and small tablets.
        final isWide = constraints.maxWidth >= 760;
        final basePadding = Breakpoints.isMobile(constraints.maxWidth)
            ? const EdgeInsets.all(AppSpacing.s16)
            : const EdgeInsets.all(AppSpacing.s24);
        final padding = basePadding.copyWith(
          bottom:
              basePadding.bottom + 64 + MediaQuery.paddingOf(context).bottom,
        );

        final allGroupsSingleColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            accountGroup,
            const SizedBox(height: AppSpacing.s20),
            numbersGroup,
            const SizedBox(height: AppSpacing.s20),
            appearanceGroup,
            const SizedBox(height: AppSpacing.s20),
            planningGroup,
            const SizedBox(height: AppSpacing.s20),
            aiGroup,
            const SizedBox(height: AppSpacing.s20),
            dataGroup,
            const SizedBox(height: AppSpacing.s20),
            domainsGroup,
            const SizedBox(height: AppSpacing.s20),
            aboutGroup,
            const SizedBox(height: AppSpacing.s20),
            advancedGroup,
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
                        const SizedBox(height: AppSpacing.s20),
                        numbersGroup,
                        const SizedBox(height: AppSpacing.s20),
                        appearanceGroup,
                        const SizedBox(height: AppSpacing.s20),
                        planningGroup,
                      ],
                    )
                  : allGroupsSingleColumn,
              secondary: isWide
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        aiGroup,
                        const SizedBox(height: AppSpacing.s20),
                        dataGroup,
                        const SizedBox(height: AppSpacing.s20),
                        domainsGroup,
                        const SizedBox(height: AppSpacing.s20),
                        aboutGroup,
                        const SizedBox(height: AppSpacing.s20),
                        advancedGroup,
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
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
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

/// iOS-style inset-grouped section header — small, all-caps, muted,
/// with a subtle left accent bar for visual anchoring.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s20,
        AppSpacing.s12,
        AppSpacing.s6,
      ),
      child: Row(
        children: [
          Container(
            width: 2,
            height: AppSpacing.s12,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: AppOpacity.highlight),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            title.toUpperCase(),
            style: context.theme.typography.xs2.copyWith(
              color: colors.mutedForeground,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient fade divider between adjacent rows in the same SoftCard
/// section — uses the shared [AppGradientDivider] for consistency.
class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const AppGradientDivider();
}

class _AccountSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isLocalOnly =
        ref.watch(authControllerProvider).value is AuthLocalOnly;

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
        onTap: () => context.go('${AppRoutes.login}?mode=upgrade'),
      );
    }
    return InlineLinkRow(
      icon: FLucideIcons.monitor,
      label: l10n.settingsDevicesTitle,
      subtitle: l10n.settingsDevicesSubtitle,
      onTap: () => context.goNamed(AppRouteNames.devices),
      trailing: Icon(
        FLucideIcons.logOut,
        size: AppIconSizes.h18,
        color: context.theme.colors.mutedForeground,
      ),
      onTrailingTap: () => _showSwitchToLocalSheet(context, ref),
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
    );
  }
}

/// Sheet body for confirming the cloud → local-only downgrade.
/// Handles its own busy state internally.
class _SwitchToLocalSheetBody extends ConsumerStatefulWidget {
  const _SwitchToLocalSheetBody();

  @override
  ConsumerState<_SwitchToLocalSheetBody> createState() =>
      _SwitchToLocalSheetBodyState();
}

class _SwitchToLocalSheetBodyState
    extends ConsumerState<_SwitchToLocalSheetBody> {
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).switchToLocalOnly();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        0,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.settingsSwitchToLocalConfirmBody,
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.s20),
          FButton(
            variant: FButtonVariant.outline,
            onPress: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.primary,
            onPress: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(
                    width: AppIconSizes.h18,
                    height: AppIconSizes.h18,
                    child: FCircularProgress(
                      size: FCircularProgressSizeVariant.sm,
                    ),
                  )
                : Text(l10n.settingsSwitchToLocal),
          ),
        ],
      ),
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
          padding: EdgeInsets.fromLTRB(
            AppSpacing.s14,
            0,
            AppSpacing.s14,
            AppSpacing.s8,
          ),
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
                  style: context.theme.typography.sm,
                ),
                const SizedBox(height: AppSpacing.s2),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s14,
        AppSpacing.s10,
        AppSpacing.s14,
        AppSpacing.s10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.slidersHorizontal,
                size: AppIconSizes.h18,
                color: colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s12),
              Text(
                l10n.settingsRiskAppetiteLabel,
                style: context.theme.typography.sm,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s6,
            runSpacing: AppSpacing.s6,
            children: [
              for (final option in _appetiteOptionsForChips(l10n))
                _SettingsChoicePill(
                  label: option.label,
                  selected: appetite == option.value,
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

class _SettingsChoicePill extends StatelessWidget {
  const _SettingsChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onTap,
      child: AnimatedContainer(
        duration: Motion.medium,
        curve: Motion.standardDecelerate,
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s6,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: AppOpacity.subtle)
              : colors.muted.withValues(alpha: AppOpacity.faint),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.prominent)
                : colors.border.withValues(alpha: AppOpacity.muted),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: AppOpacity.faint),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.theme.typography.xs.copyWith(
            color: selected ? colors.primary : colors.foreground,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
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
