/// App-level shell chrome contribution.
///
/// `core/shell/shell_chrome.dart` owns the feature-facing primitives. This
/// file wires those primitives to app-owned navigation and widgets: the
/// domain switcher, command palette, and Settings route.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai/composition/ask_ai.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../core/shell/domain_shell.dart';
import '../../core/shell/domain_switcher.dart';
import '../../core/shell/settings_route_paths.dart';
import '../../core/shell/shell_chrome.dart';
import '../../core/shell/sync_attention.dart';
import '../../core/shortcuts/shortcut_intents.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../routing/route_paths.dart';

List<Override> appShellChromeOverrides() {
  return [
    shellChromeBuildersProvider.overrideWith((ref) => appShellChromeBuilders),
    domainSwitcherHomePathProvider.overrideWithValue(AppRoutes.life),
  ];
}

const ShellChromeBuilders appShellChromeBuilders = ShellChromeBuilders(
  leadingBuilder: _buildShellLeading,
  headerActionsBuilder: _buildShellGlobalActions,
  openAiAction: askAi,
);

Widget _buildShellLeading(BuildContext context, WidgetRef ref) {
  return const DomainSwitcherChip();
}

/// The global Search + Settings header actions.
///
/// Search opens the cross-domain command palette via the global
/// [OpenCommandPaletteIntent] action (registered in
/// `core/shortcuts/global_shortcuts_scope.dart`); Settings pushes
/// `/settings` outside the shell so back returns to the current tab.
List<ShellHeaderActionSpec> _buildShellGlobalActions(
  BuildContext context,
  WidgetRef ref,
) {
  final l10n = AppLocalizations.of(context);
  final attention = ref.watch(syncAttentionProvider);
  return <ShellHeaderActionSpec>[
    if (attention != null)
      ShellHeaderActionSpec(
        icon: FLucideIcons.cloudOff,
        label: syncOverviewMessage(l10n, attention),
        onPress: () => context.push(SettingsRoutes.sync),
        order: -1,
      ),
    ShellHeaderActionSpec(
      icon: FLucideIcons.search,
      label: l10n.navSearch,
      onPress: () =>
          Actions.maybeInvoke(context, const OpenCommandPaletteIntent()),
      order: 100,
    ),
    ShellHeaderActionSpec(
      icon: FLucideIcons.settings,
      label: l10n.navSettingsTooltip,
      onPress: () => context.push(SettingsRoutes.root),
      order: 110,
    ),
  ];
}

/// Compact domain switcher chip for a header prefix slot.
///
/// Renders the active domain's icon + a chevron; tapping opens
/// [showDomainSwitcherSheet]. On the Life hub it renders as an icon-only
/// workspace control: no individual domain is active there, and showing the
/// fallback Finance label incorrectly implies domain ownership. A
/// single-domain install gets one compact direct link on the Life hub instead
/// of a redundant in-content domain navigation section.
class DomainSwitcherChip extends ConsumerWidget {
  const DomainSwitcherChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Visible on phones AND tablets: below [Breakpoints.shellDesktop] the
    // always-visible domain dock is absent, so the header chip is the
    // discoverable way to leave the current domain. The old `>= mobile`
    // guard left every 600–1280px viewport with no switcher at all.
    if (MediaQuery.sizeOf(context).width >= Breakpoints.shellDesktop) {
      return const SizedBox.shrink();
    }
    final specs = ref.watch(activeDomainShellsProvider);
    if (specs.isEmpty) return const SizedBox.shrink();
    final homePath = ref.watch(domainSwitcherHomePathProvider);

    final path = GoRouter.of(context).routeInformationProvider.value.uri.path;
    final isLifeHub = path == homePath;
    final single = specs.length == 1 ? specs.single : null;
    final singleTarget = single != null && single.tabs.isNotEmpty
        ? single.tabs.first.routePath
        : null;
    final isSingleHomeLink =
        isLifeHub && singleTarget != null && singleTarget != path;
    if (specs.length == 1 && !isSingleHomeLink) {
      return const SizedBox.shrink();
    }
    final active = activeSpecForPath(specs, path);
    final colors = context.theme.colors;
    // The chip icon carries the shown domain's accent hue when its pack
    // declares one; unregistered scopes (tests, reduced builds) and the
    // neutral Life workspace icon keep the global primary.
    final shownScope = isSingleHomeLink
        ? single!.scope
        : isLifeHub
        ? null
        : active.scope;
    final chipAccent = shownScope == null
        ? null
        : resolveDomainAccent(
            ref.watch(domainPackRegistryProvider),
            shownScope,
            context.appTheme.brightness,
          );
    final l10n = AppLocalizations.of(context);
    final semanticsLabel = isSingleHomeLink
        ? single!.label
        : isLifeHub
        ? l10n.shellSwitchDomainTitle
        : active.label;

    return Semantics(
      label: semanticsLabel,
      button: true,
      child: FTappable(
        onPress: isSingleHomeLink
            ? () => context.go(singleTarget)
            : () => showDomainSwitcherSheet(context, specs, homePath),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppControlHeights.touchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSingleHomeLink
                    ? single!.selectedIcon
                    : isLifeHub
                    ? FLucideIcons.layers
                    : active.selectedIcon,
                size: AppIconSizes.sm,
                color: chipAccent ?? colors.primary,
              ),
              if (!isLifeHub || isSingleHomeLink) ...[
                const SizedBox(width: AppSpacing.s6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 76),
                  child: Text(
                    isSingleHomeLink ? single!.label : active.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.captionLabelStyle.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.s4),
              Icon(
                isSingleHomeLink
                    ? FLucideIcons.chevronRight
                    : FLucideIcons.chevronDown,
                size: AppIconSizes.xs,
                color: colors.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
