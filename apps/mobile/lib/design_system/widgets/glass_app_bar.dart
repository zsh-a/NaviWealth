import 'package:flutter/material.dart';

/// Flat AppBar replacement. The original wrapper rendered a frosted-glass
/// surface via `liquid_glass_widgets`; after the Forui migration this is
/// a plain Material `AppBar` whose styling is provided by `AppTheme`
/// (transparent surface tint, no elevation, hairline divider implied by
/// the page padding). Public API unchanged so existing call sites compile.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
    this.quality, // retained for binary compat; ignored
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;

  /// Glass-era quality knob. No-op now; keeps the call sites unchanged.
  final Object? quality;

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      bottom: bottom,
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: centerTitle ?? false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    );
  }
}
