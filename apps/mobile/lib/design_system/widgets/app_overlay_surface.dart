import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Canonical surface for floating overlay cards — centered dialogs, the
/// command palette, and desktop floating panels.
///
/// One recipe for every overlay card in the app: opaque background,
/// `AppRadius.lg` corners, a hairline border, and the shared elevation
/// shadow. Modal bottom sheets are the deliberate exception — they keep the
/// frosted [AppSheetSurface] glass recipe.
class AppOverlaySurface extends StatelessWidget {
  const AppOverlaySurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.lg)),
    this.clip = false,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Clips the child to [borderRadius] — for palette-style surfaces whose
  /// content (headers, list rows) paints to the card edge.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: borderRadius,
        border: Border.all(color: colors.border, width: AppStroke.hairline),
        boxShadow: AppShadow.desktopSheet,
      ),
      child: child,
    );
    if (!clip) return decorated;
    return ClipRRect(borderRadius: borderRadius, child: decorated);
  }
}

/// Standard constraints for anchored popover menus on pointer platforms.
///
/// The four popover call sites in the app used to hand-tune their own
/// ranges; pick from these two instead of inventing a new interval.
const FPortalConstraints kAppPopoverMenuConstraints = FPortalConstraints(
  minWidth: 208,
  maxWidth: 280,
  maxHeight: 360,
);

/// Roomier variant for selection menus with subtitles and checkmarks.
const FPortalConstraints kAppPopoverSelectionConstraints = FPortalConstraints(
  minWidth: 260,
  maxWidth: 340,
  maxHeight: 420,
);

/// Pointer-hover fill for menu/popover rows.
///
/// Selected rows get a solid `muted` fill as the single emphasis; unselected
/// rows reveal a lighter tint of the same fill on hover, animated over
/// [Motion.fast]. Harmless on touch platforms, where hover never fires.
class AppHoverFill extends StatefulWidget {
  const AppHoverFill({
    super.key,
    required this.child,
    this.selected = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.sm)),
  });

  final Widget child;
  final bool selected;
  final BorderRadius borderRadius;

  @override
  State<AppHoverFill> createState() => _AppHoverFillState();
}

class _AppHoverFillState extends State<AppHoverFill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotionPolicy.duration(context, Motion.fast),
        curve: Motion.standardDecelerate,
        decoration: BoxDecoration(
          color: widget.selected
              ? colors.muted
              : _hovered
              ? colors.muted.withValues(alpha: AppOpacity.prominent)
              : Colors.transparent,
          borderRadius: widget.borderRadius,
        ),
        child: widget.child,
      ),
    );
  }
}
