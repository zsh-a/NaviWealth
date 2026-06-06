/// Cross-domain shell chrome — the domain switcher + the global Search /
/// Settings actions that every domain surfaces the same way.
///
/// `docs/lifeos-shell.md` §1 splits the UI into a cross-domain shell layer
/// (search / settings / domain switch — domain-agnostic, always reachable)
/// and a per-domain tab layer. Before this file those global actions were
/// scattered: Search was a Finance-only middle slot in the bottom nav,
/// Settings hung off the Finance Today header avatar, and domain switching
/// was a hidden gesture. This file folds global actions into the one header
/// each tab page already renders ([ShellTabScaffold]) plus an in-content
/// variant ([ShellActionRow]) for the Today greeting, which has no
/// `FHeader`.
///
/// Layering: the presentation primitive ([DomainTabScaffold]) stays a
/// `design_system` leaf with generic `leading` / `actions` slots; the
/// *composition* (which provider feeds the chip, where Search routes) is an
/// `app`-layer concern and lives here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/shell/domain_shell.dart';
import '../core/shortcuts/shortcut_intents.dart';
import '../design_system/design_system.dart';
import '../l10n/gen/app_localizations.dart';
import 'domain_switcher.dart';
import 'route_paths.dart';

/// Width at or above which the persistent left dock + sidebar own the
/// global chrome, so the header/greeting don't repeat it.
const double kTabBarOffset = 80;
const double _desktopChromeBreakpoint = Breakpoints.desktop;

bool _showInlineChrome(BuildContext context) =>
    MediaQuery.sizeOf(context).width < _desktopChromeBreakpoint;

/// Top-level tab / hub scaffold *with* the cross-domain shell chrome.
///
/// Wraps [DomainTabScaffold] and injects the domain switcher chip
/// ([leading]) plus the global Search / Settings actions after the page's
/// own [actions]. Domains pass only their own concerns (title, body,
/// domain actions); the chrome is identical by construction.
class ShellTabScaffold extends StatelessWidget {
  const ShellTabScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.childPad = false,
    this.collapseOnScroll = true,
  });

  /// Header title, e.g. `l10n.navActivity` or `'今日 · HealthOS'`.
  final String title;

  /// Page body — owns its own scroll + padding.
  final Widget child;

  /// Domain-owned trailing header actions (`+`, filter, …). The global
  /// Search / Settings actions are appended automatically.
  final List<Widget> actions;

  /// Forwarded to [FScaffold.childPad].
  final bool childPad;

  /// Forwarded to [DomainTabScaffold.collapseOnScroll].
  final bool collapseOnScroll;

  @override
  Widget build(BuildContext context) {
    final inline = _showInlineChrome(context);
    return DomainTabScaffold(
      title: title,
      childPad: childPad,
      collapseOnScroll: collapseOnScroll,
      leading: inline ? const DomainSwitcherChip() : null,
      actions: [...actions, if (inline) ...shellGlobalActions(context)],
      child: child,
    );
  }
}

/// The global Search + Settings header actions, as `FHeaderAction`s for
/// use in an [FHeader.nested] `suffixes` list.
///
/// Search opens the cross-domain command palette via the global
/// [OpenCommandPaletteIntent] action (registered in
/// `core/shortcuts/global_shortcuts_scope.dart`); Settings pushes
/// `/settings` outside the shell so back returns to the current tab.
List<Widget> shellGlobalActions(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return <Widget>[
    FHeaderAction(
      icon: const Icon(FLucideIcons.search),
      semanticsLabel: l10n.navSearch,
      onPress: () =>
          Actions.maybeInvoke(context, const OpenCommandPaletteIntent()),
    ),
    FHeaderAction(
      icon: const Icon(FLucideIcons.settings),
      semanticsLabel: l10n.navSettingsTooltip,
      onPress: () => context.push(AppRoutes.settings),
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
    final specs = ref.watch(activeDomainShellsProvider);
    if (specs.length < 2) return const SizedBox.shrink();

    final path = GoRouter.of(context).routeInformationProvider.value.uri.path;
    final active = activeSpecForPath(specs, path);
    final colors = context.theme.colors;

    return Semantics(
      label: active.label,
      button: true,
      child: FTappable(
        onPress: () => showDomainSwitcherSheet(context, specs),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active.selectedIcon,
                size: AppIconSizes.md,
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

/// In-content variant of the shell chrome for surfaces without an
/// `FHeader` — currently the Today greeting header, which is an editorial
/// title rendered inside the scroll body. Mirrors [shellGlobalActions]:
/// domain chip (when multi-domain) + Search + Settings, gated off on
/// desktop where the dock / sidebar own them.
class ShellActionRow extends ConsumerWidget {
  const ShellActionRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_showInlineChrome(context)) return const SizedBox.shrink();
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
          onPress: () => context.push(AppRoutes.settings),
        ),
      ],
    );
  }
}

/// 40dp tappable icon used by [ShellActionRow]. Matches the visual weight
/// of the header `FHeaderAction`s so the in-content variant reads the same
/// as the headered pages.
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
    final colors = context.theme.colors;
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: FTappable(
          onPress: onPress,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: AppIconSizes.md, color: colors.foreground),
          ),
        ),
      ),
    );
  }
}
