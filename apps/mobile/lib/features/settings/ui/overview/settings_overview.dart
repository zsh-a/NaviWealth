import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_state.dart';
import '../../../../core/auth/providers.dart' as auth_providers;
import '../../../../core/config/app_version.dart';
import '../../../../core/logging/crash_reporting_preference.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../core/security/biometric_auth_service.dart';
import '../../../../core/security/biometric_lock_preferences.dart';
import '../../../../core/shell/auth_route_paths.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../../core/update/native_update.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

part 'settings_overview_account.dart';
part 'settings_overview_preferences.dart';
part 'settings_overview_sections.dart';

/// Global settings, with data controls before visual customization.
class SettingsOverview extends ConsumerWidget {
  const SettingsOverview({super.key});

  static const double _twoColumnBreakpoint = Breakpoints.contentTwoColumn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    final accountGroup = AppEntrance(
      role: AppMotionRole.decorative,
      child: _Section(
        title: l10n.settingsAccountSection,
        child: _AccountSection(),
      ),
    );
    final appearanceGroup = AppEntrance(
      role: AppMotionRole.decorative,
      child: _Section(
        child: InlineLinkRow(
          icon: FLucideIcons.palette,
          label: l10n.settingsAppearanceSection,
          subtitle: l10n.settingsAppearanceSummary,
          onTap: () => context.pushNamed(SettingsRouteNames.appearance),
        ),
      ),
    );
    final aiGroup = AppEntrance(
      role: AppMotionRole.decorative,
      child: _Section(
        child: InlineLinkRow(
          icon: FLucideIcons.sparkles,
          label: l10n.settingsAiHubTitle,
          subtitle: l10n.settingsAiHubSubtitle,
          onTap: () => context.pushNamed(SettingsRouteNames.ai),
        ),
      ),
    );
    final isLocalOnly =
        ref.watch(auth_providers.authStateProvider) is AuthLocalOnly;
    final dataGroup = AppEntrance(
      role: AppMotionRole.decorative,
      child: _Section(
        title: l10n.settingsDataSection,
        child: Column(
          children: [
            if (!isLocalOnly) ...[
              InlineLinkRow(
                icon: FLucideIcons.refreshCw,
                label: l10n.settingsSyncTitle,
                subtitle: l10n.settingsSyncSubtitle,
                onTap: () => context.pushNamed(SettingsRouteNames.sync),
              ),
              const AppGroupedDivider(),
            ],
            InlineLinkRow(
              icon: FLucideIcons.database,
              label: l10n.settingsDataManagementTitle,
              subtitle: l10n.settingsDataManagementSubtitle,
              onTap: () => context.pushNamed(SettingsRouteNames.dataManagement),
            ),
            const AppGroupedDivider(),
            InlineLinkRow(
              icon: FLucideIcons.cloudUpload,
              label: l10n.settingsDataTitle,
              subtitle: l10n.settingsDataSubtitle,
              onTap: () => context.pushNamed(SettingsRouteNames.backup),
            ),
          ],
        ),
      ),
    );
    final notificationsPrivacyGroup = AppEntrance(
      role: AppMotionRole.decorative,
      child: _Section(
        title: l10n.settingsNotificationsPrivacySection,
        child: Column(
          children: [
            InlineLinkRow(
              icon: FLucideIcons.bell,
              label: l10n.settingsNotificationsTitle,
              subtitle: l10n.settingsNotificationsSubtitle,
              onTap: () => context.pushNamed(SettingsRouteNames.notifications),
            ),
            const AppGroupedDivider(),
            const _BiometricUnlockRow(),
            const AppGroupedDivider(),
            const _CrashReportingRow(),
            const AppGroupedDivider(),
            const _ProductMetricsRow(),
          ],
        ),
      ),
    );
    // Domain-specific settings live one level down so the overview stays
    // focused on global preference categories.
    final domainsGroup = AppEntrance(
      role: AppMotionRole.decorative,
      child: _Section(
        child: InlineLinkRow(
          icon: FLucideIcons.blocks,
          label: l10n.settingsDomainsTitle,
          subtitle: l10n.settingsDomainsSubtitle,
          onTap: () => context.pushNamed(SettingsRouteNames.domains),
        ),
      ),
    );
    // Logs viewer is exposed in release as well — the talker history is
    // already kept in memory in every build, and dogfood users need a
    // way to copy diagnostics out (e.g. Health Connect permission flow)
    // without a debug attach.
    final advancedGroup = AppEntrance(
      role: AppMotionRole.decorative,
      child: _Section(
        title: l10n.settingsAboutDiagnosticsSection,
        child: Column(
          children: [
            InlineLinkRow(
              icon: FLucideIcons.settings2,
              label: l10n.settingsAdvancedHubTitle,
              subtitle: l10n.settingsAdvancedHubSubtitle,
              onTap: () => context.pushNamed(SettingsRouteNames.advanced),
            ),
            const AppGroupedDivider(),
            const _AboutTile(),
          ],
        ),
      ),
    );

    final groups = <Widget>[
      accountGroup,
      dataGroup,
      domainsGroup,
      aiGroup,
      appearanceGroup,
      notificationsPrivacyGroup,
      advancedGroup,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Settings rows carry explanatory copy, so wait for a real desktop
        // content width before introducing columns. The wide layout pairs
        // adjacent sections to preserve the mobile reading order.
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

        final allGroupsSingleColumn = _SettingsGroupColumn(groups: groups);

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            AdaptiveContentFrame(
              maxWidth: isWide
                  ? AdaptiveMaxWidth.page
                  : AdaptiveMaxWidth.narrow,
              layout: AdaptiveFrameLayout.singleColumn,
              padding: padding,
              primary: isWide
                  ? _SettingsWideGrid(groups: groups)
                  : allGroupsSingleColumn,
            ),
          ],
        );
      },
    );
  }
}

class _SettingsGroupColumn extends StatelessWidget {
  const _SettingsGroupColumn({required this.groups});

  final List<Widget> groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.s20),
          groups[index],
        ],
      ],
    );
  }
}

class _SettingsWideGrid extends StatelessWidget {
  const _SettingsWideGrid({required this.groups});

  final List<Widget> groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < groups.length; index += 2) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: groups[index]),
              const SizedBox(width: AppSpacing.s24),
              Expanded(
                child: index + 1 < groups.length
                    ? groups[index + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          if (index + 2 < groups.length) const SizedBox(height: AppSpacing.s20),
        ],
      ],
    );
  }
}
