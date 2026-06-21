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
import '../../auth/data/auth_controller.dart';
import 'inline_setting_row.dart';

/// Settings landing page — iOS-style inset-grouped sections.
///
/// Section order maps to user mental model (most-personal → least):
///
///   1. Account            cloud / device identity
///   2. Appearance         theme / market color / language
///   3. AI                 privacy → LLM provider → transparency
///   4. Data               sync + backup
///   5. LifeOS Domains     FinanceOS / HealthOS / KnowledgeOS
///   6. Diagnostics        version / logs / performance
///
/// The previous `_AccountHeader` decorative tile is gone — the page
/// title comes from `appSubPageHeader` in `settings_page.dart`, so the
/// section list starts at the top with no redundant chrome.
class SettingsOverview extends ConsumerWidget {
  const SettingsOverview({super.key});

  static const double _twoColumnBreakpoint = 760;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    final accountGroup = _Section(
      title: l10n.settingsAccountSection,
      child: _AccountSection(),
    );
    final appearanceGroup = _Section(
      title: l10n.settingsAppearanceSection,
      child: const _AppearanceSection(),
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
          const AppGradientDivider(),
          InlineLinkRow(
            icon: FLucideIcons.key,
            label: l10n.settingsAiLlmTitle,
            subtitle: l10n.settingsAiLlmSubtitle,
            onTap: () => context.goNamed(AppRouteNames.aiLlm),
          ),
          const AppGradientDivider(),
          InlineLinkRow(
            icon: FLucideIcons.eye,
            label: l10n.settingsAiTransparencyTitle,
            subtitle: l10n.settingsAiTransparencySubtitle,
            onTap: () => context.goNamed(AppRouteNames.aiTransparency),
          ),
          const AppGradientDivider(),
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
            const AppGradientDivider(),
          ],
          InlineLinkRow(
            icon: FLucideIcons.cloudUpload,
            label: l10n.settingsDataTitle,
            subtitle: l10n.settingsDataSubtitle,
            onTap: () => context.goNamed(AppRouteNames.backup),
          ),
          const AppGradientDivider(),
          const _CrashReportingRow(),
        ],
      ),
    );
    // Domain-specific settings live one level down so the overview stays
    // focused on global preference categories.
    final domainsGroup = _Section(
      title: l10n.settingsDomainsSection,
      child: InlineLinkRow(
        icon: FLucideIcons.blocks,
        label: l10n.settingsDomainsTitle,
        subtitle: l10n.settingsDomainsSubtitle,
        onTap: () => context.goNamed(AppRouteNames.domains),
      ),
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
          const AppGradientDivider(),
          InlineLinkRow(
            icon: FLucideIcons.activity,
            label: l10n.settingsPerfTitle,
            subtitle: l10n.settingsPerfSubtitle,
            onTap: () => context.goNamed(AppRouteNames.performance),
          ),
          const AppGradientDivider(),
          const _AboutTile(),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two-column at a list-specific breakpoint instead of the global
        // page breakpoint — settings is
        // list-heavy and benefits from horizontal density on phones in
        // landscape, foldables, and small tablets.
        final isWide = constraints.maxWidth >= _twoColumnBreakpoint;
        final basePadding = Breakpoints.isMobile(constraints.maxWidth)
            ? const EdgeInsets.all(AppSpacing.s16)
            : const EdgeInsets.all(AppSpacing.s24);
        final padding = basePadding.copyWith(
          bottom:
              basePadding.bottom +
              AppSpacing.s64 +
              MediaQuery.paddingOf(context).bottom,
        );

        final allGroupsSingleColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            accountGroup,
            const SizedBox(height: AppSpacing.s20),
            appearanceGroup,
            const SizedBox(height: AppSpacing.s20),
            aiGroup,
            const SizedBox(height: AppSpacing.s20),
            dataGroup,
            const SizedBox(height: AppSpacing.s20),
            domainsGroup,
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
                        appearanceGroup,
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: title),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          child: child,
        ),
      ],
    );
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
            style: context.microLabelStyle.copyWith(
              color: colors.mutedForeground,
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
    return Column(
      children: [
        InlineLinkRow(
          icon: FLucideIcons.monitor,
          label: l10n.settingsDevicesTitle,
          subtitle: l10n.settingsDevicesSubtitle,
          onTap: () => context.goNamed(AppRouteNames.devices),
        ),
        const AppGradientDivider(),
        InlineLinkRow(
          icon: FLucideIcons.logOut,
          label: l10n.settingsSignOutTitle,
          subtitle: l10n.settingsSignOutSubtitle,
          trailing: Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.h18,
            color: context.theme.colors.mutedForeground,
          ),
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

/// Sheet body for confirming the cloud → local-only downgrade.
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
      await ref.read(authControllerProvider.notifier).switchToLocalOnly();
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
                  style: context.theme.typography.sm,
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
