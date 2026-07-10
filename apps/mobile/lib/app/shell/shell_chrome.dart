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
import '../../core/shell/domain_shell.dart';
import '../../core/shell/domain_switcher.dart';
import '../../core/shell/settings_route_paths.dart';
import '../../core/shell/shell_chrome.dart';
import '../../core/shortcuts/shortcut_intents.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';

List<Override> appShellChromeOverrides() {
  return [
    shellChromeBuildersProvider.overrideWith((ref) => appShellChromeBuilders),
  ];
}

const ShellChromeBuilders appShellChromeBuilders = ShellChromeBuilders(
  leadingBuilder: _buildShellLeading,
  headerActionsBuilder: _buildShellGlobalActions,
  actionRowBuilder: _buildShellActionRow,
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
  return <ShellHeaderActionSpec>[
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
/// [showDomainSwitcherSheet]. Collapses to nothing when fewer than two
/// domains are active — single-domain installs never need the switcher,
/// matching [domainDockVisibleProvider].
class DomainSwitcherChip extends ConsumerWidget {
  const DomainSwitcherChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (MediaQuery.sizeOf(context).width >= Breakpoints.mobile) {
      return const SizedBox.shrink();
    }
    final specs = ref.watch(activeDomainShellsProvider);
    if (specs.length < 2) return const SizedBox.shrink();

    final path = GoRouter.of(context).routeInformationProvider.value.uri.path;
    final active = activeSpecForPath(specs, path);
    final colors = context.theme.colors;

    // Spec-style pill selector: soft cyan-gray background, large radius,
    // no hard border, icon + chevron.
    return Semantics(
      label: active.label,
      button: true,
      child: FTappable(
        onPress: () => showDomainSwitcherSheet(context, specs),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s6,
          ),
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active.selectedIcon,
                size: AppIconSizes.sm,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpacing.s4),
              Icon(
                FLucideIcons.chevronDown,
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

/// In-content app chrome for surfaces without an `FHeader` — currently the
/// Today greeting header.
Widget _buildShellActionRow(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const DomainSwitcherChip(),
      _ShellIconButton(
        icon: FLucideIcons.search,
        tooltip: l10n.navSearch,
        onPress: () =>
            Actions.maybeInvoke(context, const OpenCommandPaletteIntent()),
      ),
      _ShellIconButton(
        icon: FLucideIcons.settings,
        tooltip: l10n.navSettingsTooltip,
        onPress: () => context.push(SettingsRoutes.root),
      ),
    ],
  );
}

/// 40dp tappable icon used by the in-content action row. Matches the visual
/// weight of the header `FHeaderAction`s so the row reads like the headered
/// pages.
class _ShellIconButton extends StatelessWidget {
  const _ShellIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPress,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(icon: icon, tooltip: tooltip, onPress: onPress);
  }
}
