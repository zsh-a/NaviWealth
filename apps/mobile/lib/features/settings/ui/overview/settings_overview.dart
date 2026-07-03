import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_state.dart';
import '../../../../core/auth/providers.dart' as auth_providers;
import '../../../../core/config/app_version.dart';
import '../../../../core/haptics/haptics.dart';
import '../../../../core/logging/crash_reporting_preference.dart';
import '../../../../core/security/biometric_auth_service.dart';
import '../../../../core/security/biometric_lock_preferences.dart';
import '../../../../core/shell/auth_route_paths.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

part 'settings_overview_account.dart';
part 'settings_overview_preferences.dart';
part 'settings_overview_sections.dart';

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
            onTap: () => context.goNamed(SettingsRouteNames.aiPrivacy),
          ),
          const AppGradientDivider(),
          InlineLinkRow(
            icon: FLucideIcons.key,
            label: l10n.settingsAiLlmTitle,
            subtitle: l10n.settingsAiLlmSubtitle,
            onTap: () => context.goNamed(SettingsRouteNames.aiLlm),
          ),
          const AppGradientDivider(),
          InlineLinkRow(
            icon: FLucideIcons.eye,
            label: l10n.settingsAiTransparencyTitle,
            subtitle: l10n.settingsAiTransparencySubtitle,
            onTap: () => context.goNamed(SettingsRouteNames.aiTransparency),
          ),
          const AppGradientDivider(),
          InlineLinkRow(
            icon: FLucideIcons.download,
            label: l10n.settingsAiModelsTitle,
            subtitle: l10n.settingsAiModelsSubtitle,
            onTap: () => context.goNamed(SettingsRouteNames.aiModels),
          ),
        ],
      ),
    );
    final isLocalOnly =
        ref.watch(auth_providers.authStateProvider) is AuthLocalOnly;
    final dataGroup = _Section(
      title: l10n.settingsDataSection,
      child: Column(
        children: [
          if (!isLocalOnly) ...[
            InlineLinkRow(
              icon: FLucideIcons.refreshCw,
              label: l10n.settingsSyncTitle,
              subtitle: l10n.settingsSyncSubtitle,
              onTap: () => context.goNamed(SettingsRouteNames.sync),
            ),
            const AppGradientDivider(),
          ],
          InlineLinkRow(
            icon: FLucideIcons.cloudUpload,
            label: l10n.settingsDataTitle,
            subtitle: l10n.settingsDataSubtitle,
            onTap: () => context.goNamed(SettingsRouteNames.backup),
          ),
          const AppGradientDivider(),
          InlineLinkRow(
            icon: FLucideIcons.bell,
            label: l10n.settingsNotificationsTitle,
            subtitle: l10n.settingsNotificationsSubtitle,
            onTap: () => context.goNamed(SettingsRouteNames.notifications),
          ),
          const AppGradientDivider(),
          const _BiometricUnlockRow(),
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
        onTap: () => context.goNamed(SettingsRouteNames.domains),
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
            onTap: () => context.goNamed(SettingsRouteNames.logs),
          ),
          const AppGradientDivider(),
          InlineLinkRow(
            icon: FLucideIcons.activity,
            label: l10n.settingsPerfTitle,
            subtitle: l10n.settingsPerfSubtitle,
            onTap: () => context.goNamed(SettingsRouteNames.performance),
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
