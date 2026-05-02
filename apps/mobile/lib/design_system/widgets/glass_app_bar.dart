import 'package:flutter/material.dart';

import '../tokens/glass_tokens.dart';
import 'glass_surface.dart';

/// Drop-in [AppBar] replacement that paints a frosted-glass surface and
/// ramps its opacity with vertical scroll.
///
/// The visual contract:
///
///  * `0px` scroll → tint alpha sits at [_alphaAtRest] (≈ 0.6 of the
///    underlying surface tint), so the page chrome reads as a true
///    overlay; the canvas behind it bleeds through.
///  * `≥ _alphaSaturatedAt` px → tint reaches the token's full surface
///    alpha (`0.72` dark / `0.82` light) so dense list rows read against
///    a near-opaque chrome that's still glass, not a flat fill.
///  * Sigma is fixed at 18 (mobile AppBar contract) and only re-clipped
///    on resize; we don't animate it because the cost of re-rendering the
///    blur kernel per scroll frame doesn't repay the visual difference.
///
/// We listen to the framework `Scrollable.of(context).position` rather
/// than wiring a [NotificationListener]: the page does not need to know
/// the AppBar exists, so it has no opinion about which scroll
/// notifications to forward. The [ScrollPosition] subscription is
/// idempotent under hot reload (Flutter sends a sentinel notification on
/// listener-add) so the alpha settles to its current value on first
/// build without a frame of "rest" first.
class GlassAppBar extends StatefulWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;

  static const double _sigma = 18;
  static const double _alphaAtRest = 0.6;
  static const double _alphaSaturatedAt = 56;

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }

  @override
  State<GlassAppBar> createState() => _GlassAppBarState();
}

class _GlassAppBarState extends State<GlassAppBar> {
  ScrollPosition? _position;
  double _scrollProgress = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (identical(next, _position)) return;
    _position?.removeListener(_onScroll);
    _position = next;
    _position?.addListener(_onScroll);
    _onScroll();
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final pos = _position;
    if (pos == null || !pos.hasPixels) {
      if (_scrollProgress != 0) setState(() => _scrollProgress = 0);
      return;
    }
    final raw = pos.pixels.clamp(0.0, GlassAppBar._alphaSaturatedAt);
    final next = raw / GlassAppBar._alphaSaturatedAt;
    if ((next - _scrollProgress).abs() < 0.01) return;
    setState(() => _scrollProgress = next);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context);
    const restAlpha = GlassAppBar._alphaAtRest;
    final fullAlpha = tokens.surfaceColor.a;
    final alpha = restAlpha + (fullAlpha - restAlpha) * _scrollProgress;

    return GlassSurface(
      sigma: GlassAppBar._sigma,
      alpha: alpha,
      border: Border(
        bottom: BorderSide(color: tokens.hairlineColor, width: 1),
      ),
      child: AppBar(
        title: widget.title,
        leading: widget.leading,
        actions: widget.actions,
        bottom: widget.bottom,
        automaticallyImplyLeading: widget.automaticallyImplyLeading,
        centerTitle: widget.centerTitle,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
    );
  }
}
