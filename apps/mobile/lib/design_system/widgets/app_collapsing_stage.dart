import 'dart:ui' as ui show lerpDouble;

import 'package:flutter/widgets.dart';

import '../tokens/dimens_tokens.dart';
import 'app_glass.dart';

/// Default scroll distance (logical px) from rest to fully collapsed stage.
const double kAppCollapseExtent = 88;

/// Scroll-linked stage for page heroes (net worth, recovery score, focus count).
///
/// Tracks the nearest ancestor [Scrollable] via [AnimatedBuilder] and gently
/// scales the child toward [minScale] as the user scrolls down.
///
/// Place this *inside* a scroll view so [Scrollable.maybeOf] resolves.
/// Prefer wrapping the whole hero module — alignment stays top-centered.
///
/// Scroll→collapse mapping always runs (including under reduced motion). It is
/// a layout response, not a decorative animation.
class AppCollapsingStage extends StatelessWidget {
  const AppCollapsingStage({
    super.key,
    required this.child,
    this.collapseExtent = kAppCollapseExtent,
    this.minScale = 0.88,
    this.minOpacity = 0.92,
  });

  final Widget child;

  /// Scroll pixels required to reach full collapse.
  final double collapseExtent;

  /// Scale at full collapse (1 → [minScale]).
  final double minScale;

  /// Opacity at full collapse (1 → [minOpacity]). Keeps the stage legible.
  final double minOpacity;

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) {
      return child;
    }

    return AnimatedBuilder(
      animation: position,
      builder: (context, child) {
        final t = appScrollCollapseProgress(
          pixels: position.hasPixels ? position.pixels : 0,
          extent: collapseExtent,
        );
        final scale = ui.lerpDouble(1, minScale, t)!;
        final opacity = ui.lerpDouble(1, minOpacity, t)!;
        // Avoid FilterQuality.medium — it forces extra texture sampling
        // every scroll frame for a subtle visual polish that is not worth
        // the raster cost on chart-heavy dashboards.
        return Transform.scale(
          scale: scale,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.low,
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: child,
    );
  }
}

/// Maps scroll [pixels] into a 0–1 collapse progress.
double appScrollCollapseProgress({
  required double pixels,
  double extent = kAppCollapseExtent,
}) {
  final e = extent <= 0 ? 1.0 : extent;
  return (pixels / e).clamp(0.0, 1.0);
}

/// Host that owns a scrollable [body] and optional sticky summary overlay.
///
/// Listens to [ScrollNotification]s bubbling from [body] (typically a
/// [ListView]) so the sticky bar can live *outside* the scrollable while still
/// tracking progress. Pair with [AppCollapsingStage] inside the list and
/// [AppCollapsedSummaryBar] in [stickyBuilder].
class AppCollapsingScrollHost extends StatefulWidget {
  const AppCollapsingScrollHost({
    super.key,
    required this.body,
    this.stickyBuilder,
    this.collapseExtent = kAppCollapseExtent,
    this.padding = EdgeInsets.zero,
    this.primaryController,
  });

  /// Scrollable content (usually a [ListView] / [CustomScrollView]).
  final Widget body;

  /// Built above the body; receives collapse progress 0–1.
  final Widget Function(BuildContext context, double progress)? stickyBuilder;

  final double collapseExtent;

  /// Outer inset applied to the sticky bar (not the body).
  final EdgeInsetsGeometry padding;

  /// Optional authoritative scroll source for layouts with multiple nested
  /// scrollables. When set, descendant [ScrollNotification]s are ignored.
  final ScrollController? primaryController;

  @override
  State<AppCollapsingScrollHost> createState() =>
      _AppCollapsingScrollHostState();
}

class _AppCollapsingScrollHostState extends State<AppCollapsingScrollHost> {
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    widget.primaryController?.addListener(_onPrimaryScroll);
  }

  @override
  void didUpdateWidget(covariant AppCollapsingScrollHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryController == widget.primaryController) return;
    oldWidget.primaryController?.removeListener(_onPrimaryScroll);
    widget.primaryController?.addListener(_onPrimaryScroll);
  }

  @override
  void dispose() {
    widget.primaryController?.removeListener(_onPrimaryScroll);
    super.dispose();
  }

  void _onPrimaryScroll() {
    final controller = widget.primaryController;
    if (controller == null || !controller.hasClients) return;
    _updateProgress(controller.offset);
  }

  void _updateProgress(double pixels) {
    final next = appScrollCollapseProgress(
      pixels: pixels,
      extent: widget.collapseExtent,
    );
    if ((next - _progress).abs() < 0.008) return;
    setState(() => _progress = next);
  }

  bool _onScroll(ScrollNotification notification) {
    if (widget.primaryController != null) return false;
    // depth 0 = direct scrollable body; depth 1 = cockpit dual-column
    // ListViews nested one level under a Row/Column host body.
    if (notification.depth > 1) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    _updateProgress(notification.metrics.pixels);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final sticky = widget.stickyBuilder;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: sticky == null
          ? widget.body
          : Stack(
              clipBehavior: Clip.none,
              children: [
                widget.body,
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: widget.padding,
                    child: sticky(context, _progress),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Compact residual summary that fades/slides in after the hero collapses.
///
/// Always wraps [child] in a frosted glass chrome so Finance / Health /
/// Execution / Life share one sticky language. Call sites only supply the
/// inner row (label + value / badge), not another SoftCard shell.
///
/// Drive with [AppCollapsingScrollHost.stickyBuilder] progress, or pass an
/// explicit [progress] from any scroll source.
class AppCollapsedSummaryBar extends StatelessWidget {
  const AppCollapsedSummaryBar({
    super.key,
    required this.child,
    this.progress = 0,
    this.showAfter = 0.55,
    this.visible,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.s14,
      vertical: AppSpacing.s10,
    ),
  });

  /// When non-null, overrides [progress]/[showAfter] (legacy boolean API).
  final bool? visible;

  /// Collapse progress 0–1 from [AppCollapsingScrollHost] / scroll metrics.
  final double progress;

  /// Progress threshold at which the bar begins to appear.
  final double showAfter;

  /// Inner content — typically a single [Row] of label + metric.
  final Widget child;

  /// Inset inside the glass chrome.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final forced = visible;
    final double opacity;
    final double slide;
    if (forced != null) {
      opacity = forced ? 1 : 0;
      slide = forced ? 0 : -8;
    } else {
      final span = (1 - showAfter).clamp(0.08, 1.0);
      final t = ((progress - showAfter) / span).clamp(0.0, 1.0);
      opacity = t;
      slide = ui.lerpDouble(-10, 0, t)!;
    }

    final showing = opacity > 0.02;
    return IgnorePointer(
      ignoring: !showing,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, slide),
          child: _StickyGlassChrome(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Sticky residual surface — the compact counterpart of the floating dock.
class _StickyGlassChrome extends StatelessWidget {
  const _StickyGlassChrome({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppGlassSurface(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      boxShadow: AppShadow.elevation2,
      padding: padding,
      child: child,
    );
  }
}
