import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import 'scroll_state.dart';

/// Drop-in [AppBar] replacement with iOS 26 Liquid Glass rendering.
///
/// Delegates to the package's `GlassAppBar` from `liquid_glass_widgets`,
/// which provides shader-based glassmorphism plus automatic accessibility
/// fallbacks (Reduce Transparency, Reduce Motion). The app's root
/// `AdaptiveLiquidGlassLayer` (installed in `app.dart`) supplies the
/// shader render link, so individual app bars share that layer instead
/// of capturing their own backdrop.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
    this.quality,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;
  final lgw.GlassQuality? quality;

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }

  @override
  Widget build(BuildContext context) {
    final isScrolling = ScrollingScope.of(context);
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
      quality: effectiveQuality,
    );

    if (bottom == null) return appBar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [appBar, bottom!],
    );
  }
}
