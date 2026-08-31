import 'package:flutter/material.dart' show Colors, IconData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'settings_route_paths.dart';
import 'shell_preferences.dart';

/// Collapsible left sidebar for the desktop shell.
///
/// Two visual states:
///
///  * Expanded (240dp) — icon + label per destination. A slim accent marker
///    sits beside the icon on the selected row, while a whisper tint is
///    reserved for pointer hover (navigation rows and footer alike).
///  * Collapsed (72dp) — centered icons only; the label travels into the
///    [FTooltip] so a pointer hover surfaces the destination name without
///    re-flowing the layout, and the selection marker falls back to a
///    leading-edge overlay.
///
/// Labels fade in/out continuously with the animated width (see
/// [_SidebarMetrics]) instead of popping at a single breakpoint.
class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.workspace,
    this.footerActions = const <DesktopSidebarAction>[],
    this.forceCollapsed = false,
    this.accentColor,
  });

  final List<DesktopSidebarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final DesktopSidebarWorkspace? workspace;
  final List<DesktopSidebarAction> footerActions;

  /// Optional selected-destination tint (e.g. the active domain accent).
  /// Null keeps the global primary. Footer actions stay on the primary.
  final Color? accentColor;

  /// Temporarily renders the icon-only rail without changing the persisted
  /// user preference. Used by constrained desktop windows where the expanded
  /// sidebar would make content narrower than it was in the tablet tier.
  final bool forceCollapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final effectiveCollapsed = forceCollapsed || collapsed;
    return AnimatedContainer(
      duration: AppMotionPolicy.duration(context, Motion.fast),
      curve: Motion.standardDecelerate,
      width: effectiveCollapsed
          ? kSidebarCollapsedWidth
          : kSidebarExpandedWidth,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Drive layout + label opacity from the animated width, not from
            // the target preference. Icons recenter only once the rail is
            // near its collapsed width, and labels fade out before the rail
            // becomes too narrow — both directions stay overflow-free.
            final metrics = _SidebarMetrics(constraints.maxWidth);
            return DecoratedBox(
              decoration: BoxDecoration(color: context.appTheme.surfaces.card),
              child: SafeArea(
                right: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.s12),
                    if (workspace case final workspace?) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s8,
                        ),
                        child: _SidebarRow(
                          icon: workspace.icon,
                          label: workspace.label,
                          onPress: workspace.onPress,
                          collapsed: metrics.collapsed,
                          labelOpacity: metrics.labelOpacity,
                          accentColor: workspace.accentColor,
                          // The workspace slot is the brand position: give its
                          // icon a tinted tile so it never reads as a
                          // duplicate of the Today destination below.
                          iconTile: true,
                          trailing: Icon(
                            FLucideIcons.chevronsUpDown,
                            color: context.theme.colors.mutedForeground,
                            size: AppIconSizes.sm,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                    ],
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s8,
                          vertical: AppSpacing.s4,
                        ),
                        itemCount: destinations.length,
                        itemBuilder: (_, i) => _SidebarRow(
                          icon: i == selectedIndex
                              ? destinations[i].selectedIcon
                              : destinations[i].icon,
                          label: destinations[i].label,
                          selected: i == selectedIndex,
                          collapsed: metrics.collapsed,
                          labelOpacity: metrics.labelOpacity,
                          accentColor: accentColor,
                          onPress: () => onDestinationSelected(i),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    for (final action in footerActions)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s8,
                        ),
                        child: _SidebarRow(
                          icon: action.icon,
                          label: action.label,
                          emphasized: action.emphasized,
                          collapsed: metrics.collapsed,
                          labelOpacity: metrics.labelOpacity,
                          onPress: action.onPress,
                        ),
                      ),
                    // Settings and the collapse toggle share one compact
                    // footer row when expanded; the collapsed rail stacks
                    // them as centered icon rows.
                    if (metrics.collapsed) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s8,
                        ),
                        child: _SidebarRow(
                          icon: FLucideIcons.settings,
                          label: l10n.navSettings,
                          collapsed: true,
                          onPress: () => context.push(SettingsRoutes.root),
                        ),
                      ),
                      if (!forceCollapsed)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s8,
                          ),
                          child: _SidebarRow(
                            icon: FLucideIcons.chevronRight,
                            label: l10n.shellExpandSidebarShortcut,
                            collapsed: true,
                            onPress: () => ref
                                .read(sidebarCollapsedProvider.notifier)
                                .toggle(),
                          ),
                        ),
                    ] else
                      _ExpandedFooterRow(
                        settingsLabel: l10n.navSettings,
                        toggleTooltip: l10n.shellCollapseSidebarShortcut,
                        onSettings: () => context.push(SettingsRoutes.root),
                        onToggle: forceCollapsed
                            ? null
                            : () => ref
                                  .read(sidebarCollapsedProvider.notifier)
                                  .toggle(),
                      ),
                    const SizedBox(height: AppSpacing.s8),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Layout metrics derived from the sidebar's *animated* width.
///
///  * [collapsed] flips the rows to centered, icon-only layout and moves
///    labels into tooltips once the rail is near its collapsed width.
///  * [labelOpacity] ramps 0 → 1 across a 48dp fade band above that, so
///    labels cross-fade with the width animation instead of popping.
class _SidebarMetrics {
  _SidebarMetrics(double width)
    : collapsed = width < _collapsedLayoutWidth,
      labelOpacity = width < _collapsedLayoutWidth
          ? 0
          : ((width - _collapsedLayoutWidth) / _labelFadeRange).clamp(0.0, 1.0);

  final bool collapsed;
  final double labelOpacity;

  static const double _collapsedLayoutWidth = 120;
  static const double _labelFadeRange = 48;
}

/// One row in the sidebar.
class DesktopSidebarDestination {
  const DesktopSidebarDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Current workspace affordance shown above domain-local destinations.
///
/// The shell composition root supplies the label and callback, keeping this
/// shared sidebar independent of LifeOS domain types and app routes.
class DesktopSidebarWorkspace {
  const DesktopSidebarWorkspace({
    required this.icon,
    required this.label,
    required this.onPress,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;

  /// Optional tint for the workspace icon tile (e.g. the active domain
  /// accent). Null keeps the global primary.
  final Color? accentColor;
}

/// A pinned shell action rendered between navigation and Settings.
class DesktopSidebarAction {
  const DesktopSidebarAction({
    required this.icon,
    required this.label,
    required this.onPress,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final bool emphasized;
}

/// The single row primitive behind every sidebar entry: destinations,
/// workspace switcher, pinned actions, and Settings.
///
/// Selected rows use a slim accent marker next to the icon plus accent
/// foreground; a transient whisper tint communicates pointer hover. Collapsed
/// rows center their icon, surface the label through an [FTooltip], and keep
/// the marker as a leading-edge overlay.
class _SidebarRow extends StatefulWidget {
  const _SidebarRow({
    required this.icon,
    required this.label,
    required this.onPress,
    this.selected = false,
    this.emphasized = false,
    this.collapsed = false,
    this.labelOpacity = 1,
    this.iconTile = false,
    this.trailing,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final bool selected;
  final bool emphasized;
  final bool collapsed;
  final double labelOpacity;

  /// Renders the icon inside an [AppIconTile] container instead of as a bare
  /// glyph. Used by the workspace (brand) row so its icon stays visually
  /// distinct from same-shaped destination icons.
  final bool iconTile;

  /// Optional trailing affordance (e.g. the workspace switcher chevron).
  /// Only rendered in the expanded layout.
  final Widget? trailing;

  /// Optional tint replacing the global primary for the selected / icon-tile
  /// treatment (e.g. the active domain accent).
  final Color? accentColor;

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final accent = widget.accentColor ?? colors.primary;
    final foreground = widget.selected
        ? accent
        : widget.emphasized
        ? colors.primary
        : colors.mutedForeground;
    final background = _hovered
        ? colors.foreground.withValues(alpha: AppOpacity.whisper)
        : Colors.transparent;

    final Widget icon = widget.iconTile
        ? AppIconTile(icon: widget.icon, color: accent)
        : Icon(widget.icon, color: foreground, size: AppIconSizes.md);

    final row = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AppTappable(
        semanticsLabel: widget.label,
        onPress: widget.onPress,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
        child: AnimatedContainer(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          curve: Motion.standardDecelerate,
          height: AppSpacing.s40,
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Collapsed rows center their icon, so the selection marker
              // stays as a leading-edge overlay; expanded rows carry the
              // marker in the row flow next to the icon (see below).
              if (widget.collapsed)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppSelectionIndicator(
                    selected: widget.selected,
                    axis: Axis.vertical,
                    length: AppSpacing.s20,
                    color: widget.accentColor,
                  ),
                ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.collapsed ? 0 : AppSpacing.s8,
                ),
                child: Row(
                  children: [
                    if (widget.collapsed)
                      Expanded(child: Center(child: icon))
                    else ...[
                      // In-flow marker: its slot never changes size, so
                      // selection does not shift the icon or label, and the
                      // marker reads as part of the row instead of floating
                      // at the sidebar edge.
                      AppSelectionIndicator(
                        selected: widget.selected,
                        axis: Axis.vertical,
                        length: AppSpacing.s20,
                        color: widget.accentColor,
                      ),
                      const SizedBox(width: AppSpacing.s6),
                      SizedBox(
                        width: AppSpacing.s32,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: icon,
                        ),
                      ),
                      if (widget.labelOpacity > 0)
                        Expanded(
                          child: Opacity(
                            opacity: widget.labelOpacity,
                            child: Text(
                              widget.label,
                              style:
                                  (widget.selected
                                          ? context.labelStyle
                                          : context.mediumLabelStyle)
                                      .copyWith(
                                        color: widget.selected
                                            ? accent
                                            : widget.emphasized
                                            ? colors.primary
                                            : colors.foreground,
                                      ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      ?widget.trailing,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final semanticRow = Semantics(
      container: true,
      selected: widget.selected,
      child: row,
    );
    if (!widget.collapsed) return semanticRow;
    return FTooltip(
      tipBuilder: (_, _) => Text(widget.label),
      child: semanticRow,
    );
  }
}

/// Expanded footer: the Settings row with the collapse toggle parked at its
/// trailing edge, so the footer reads as one quiet control strip instead of
/// stacked full-height rows.
class _ExpandedFooterRow extends StatelessWidget {
  const _ExpandedFooterRow({
    required this.settingsLabel,
    required this.toggleTooltip,
    required this.onSettings,
    required this.onToggle,
  });

  final String settingsLabel;
  final String toggleTooltip;
  final VoidCallback onSettings;

  /// Null when the sidebar is force-collapsed by the viewport and the user
  /// preference toggle does not apply.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      child: SizedBox(
        height: AppSpacing.s40,
        child: Row(
          children: [
            Expanded(
              child: _FooterHoverRegion(
                semanticsLabel: settingsLabel,
                onPress: onSettings,
                child: Row(
                  children: [
                    SizedBox(
                      width: AppSpacing.s32,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          FLucideIcons.settings,
                          color: context.theme.colors.mutedForeground,
                          size: AppIconSizes.md,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        settingsLabel,
                        style: context.mediumLabelStyle.copyWith(
                          color: context.theme.colors.foreground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onToggle case final onToggle?)
              FTooltip(
                tipBuilder: (_, _) => Text(toggleTooltip),
                child: _FooterHoverRegion(
                  semanticsLabel: toggleTooltip,
                  onPress: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s8),
                    child: Icon(
                      FLucideIcons.chevronLeft,
                      color: context.theme.colors.mutedForeground,
                      size: AppIconSizes.sm,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shared hover-fill wrapper for the expanded footer controls.
class _FooterHoverRegion extends StatefulWidget {
  const _FooterHoverRegion({
    required this.semanticsLabel,
    required this.onPress,
    required this.child,
  });

  final String semanticsLabel;
  final VoidCallback onPress;
  final Widget child;

  @override
  State<_FooterHoverRegion> createState() => _FooterHoverRegionState();
}

class _FooterHoverRegionState extends State<_FooterHoverRegion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AppTappable(
        semanticsLabel: widget.semanticsLabel,
        onPress: widget.onPress,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
        child: AnimatedContainer(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          curve: Motion.standardDecelerate,
          decoration: BoxDecoration(
            color: _hovered
                ? context.theme.colors.foreground.withValues(
                    alpha: AppOpacity.whisper,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
          child: widget.child,
        ),
      ),
    );
  }
}
