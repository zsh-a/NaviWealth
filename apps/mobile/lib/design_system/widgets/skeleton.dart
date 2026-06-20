import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Pulsing placeholder rectangle for skeleton screens.
///
/// Used in lieu of a spinner while a card or list hydrates its first data
/// — under local-first reads (< 50ms) a spinner reads as a flash. The
/// surface tones come from the active [ColorScheme] so the effect inverts
/// cleanly under dark mode.
///
/// The shimmer animation respects the system "reduce motion" setting via
/// [MediaQueryData.disableAnimations] and the explicit [shimmer] flag.
/// When motion is disabled the widget renders a static block of the base
/// tone so layout still telegraphs "something is loading here" without
/// any movement.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 4,
    this.shimmer = true,
  });

  /// Optional explicit width. When `null` the box stretches to fill its
  /// parent — useful inside a [Column] / [Row] where the parent already
  /// constrains width.
  final double? width;

  /// Box height in logical pixels.
  final double height;

  /// Corner radius. Defaults to [4] so a row of skeleton text
  /// reads as text rather than a chip.
  final double radius;

  /// Whether to run the shimmer sweep. Set to false to render a static
  /// block — used in tests and for callers that want to suppress motion
  /// without relying on the platform setting.
  final bool shimmer;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Motion.shimmerCycle;

  late final AnimationController _controller;

  bool _running = false;

  @override
  void initState() {
    super.initState();
    // Eager init (not `late final` lazy) so dispose() never has to
    // trigger the AnimationController constructor on a deactivated
    // element — the ticker mixin's TickerMode ancestor lookup would
    // assert otherwise when shimmer was never started.
    _controller = AnimationController(vsync: this, duration: _period);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SkeletonBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final shouldRun = widget.shimmer && !reduceMotion;
    if (shouldRun == _running) return;
    _running = shouldRun;
    if (shouldRun) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final base = colors.muted;
    final highlight = Color.alphaBlend(
      colors.foreground.withValues(alpha: AppOpacity.faint),
      base,
    );

    final box = SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: _running
            ? RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _ShimmerPainter(
                      progress: _controller.value,
                      base: base,
                      highlight: highlight,
                    ),
                  ),
                ),
              )
            : ColoredBox(color: base, child: const SizedBox.expand()),
      ),
    );

    // Skeletons are decorative — screen readers should hear the live
    // result when it lands, not "loading" repeated per shimmer cell.
    return ExcludeSemantics(child: box);
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({
    required this.progress,
    required this.base,
    required this.highlight,
  });

  final double progress;
  final Color base;
  final Color highlight;

  // Cached Paint objects — avoid per-frame allocation.
  late final _basePaint = Paint()..color = base;
  final _shaderPaint = Paint();

  // Cached gradient — only the shader rect changes per frame.
  late final _gradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      base.withValues(alpha: AppOpacity.transparent),
      highlight,
      base.withValues(alpha: AppOpacity.transparent),
    ],
    stops: const [0.0, 0.5, 1.0],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, _basePaint);

    final bandWidth = size.width * 0.5;
    final dx = -bandWidth + (size.width + bandWidth) * progress;
    _shaderPaint.shader = _gradient.createShader(
      Rect.fromLTWH(dx, 0, bandWidth, size.height),
    );
    canvas.drawRect(rect, _shaderPaint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.base != base ||
        oldDelegate.highlight != highlight;
  }
}

/// Card-shaped placeholder. Pairs visually with the production [Card] used
/// across the app (same radius, surface tone, and padding) so swapping in
/// real data does not jolt the layout.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.s20),
  });

  /// Placeholder layout — typically a [Column] / [Row] of [SkeletonBox]es
  /// roughly mirroring the card's final content.
  final Widget child;

  /// Padding inside the card, defaulting to [AppSpacing.s20] to match
  /// the hero cards (NetWorth / Allocation / Trend). Pass
  /// `EdgeInsets.all(AppSpacing.s16)` for compact cards.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return FCard.raw(
      child: Padding(padding: padding, child: child),
    );
  }
}
