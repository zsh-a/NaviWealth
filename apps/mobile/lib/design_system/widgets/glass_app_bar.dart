import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

/// Drop-in [AppBar] replacement with iOS 26 Liquid Glass rendering.
///
/// Delegates to the package's `GlassAppBar` (from `liquid_glass_widgets`)
/// which provides shader-based glassmorphism with automatic accessibility
/// fallbacks (Reduce Transparency, Reduce Motion).
///
/// Use `useOwnLayer: true` when the app bar is NOT inside a
/// `LiquidGlassLayer` / `GlassBackdropScope` (the default for most pages).
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
    this.useOwnLayer = true,
    this.quality,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;
  final bool useOwnLayer;
  final lgw.GlassQuality? quality;

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }

  @override
  Widget build(BuildContext context) {
    final appBar = lgw.GlassAppBar(
      title: title,
      leading: leading,
      actions: actions,
      centerTitle: centerTitle ?? true,
      preferredSize: const Size.fromHeight(kToolbarHeight),
      useOwnLayer: useOwnLayer,
      quality: quality,
    );

    if (bottom == null) return appBar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [appBar, bottom!],
    );
  }
}
