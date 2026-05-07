import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import 'scroll_state.dart';

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
    return ValueListenableBuilder<bool>(
      valueListenable: isScrollingNotifier,
      builder: (context, isScrolling, _) {
        final effectiveLeading =
            leading ??
            (automaticallyImplyLeading && Navigator.canPop(context)
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () => Navigator.pop(context),
                  )
                : null);
        final effectiveQuality =
            quality ?? (isScrolling ? lgw.GlassQuality.minimal : null);

        final appBar = lgw.GlassAppBar(
          title: title,
          leading: effectiveLeading,
          actions: actions,
          centerTitle: centerTitle ?? true,
          preferredSize: const Size.fromHeight(kToolbarHeight),
          useOwnLayer: useOwnLayer,
          quality: effectiveQuality,
        );

        if (bottom == null) return appBar;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [appBar, bottom!],
        );
      },
    );
  }
}
