import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// Briefly reveals changed content without replacing its live widget subtree.
///
/// Navigation shells keep their Navigators, scroll positions and form state.
/// The first frame is fully visible; only [transitionKey] changes animate.
/// An interrupted reveal continues from its current opacity, with no queue
/// and no outgoing forms kept alive behind the active content.
class AppContentReveal extends StatefulWidget {
  const AppContentReveal({
    super.key,
    required this.transitionKey,
    required this.child,
    this.duration = Motion.navigationSwitch,
    this.offset = Offset.zero,
  });

  final Object? transitionKey;
  final Widget child;
  final Duration duration;
  final Offset offset;

  @override
  State<AppContentReveal> createState() => _AppContentRevealState();
}

class _AppContentRevealState extends State<AppContentReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);
  late final _opacity = CurvedAnimation(
    parent: _controller,
    curve: Motion.standardDecelerate,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateDuration();
  }

  void _updateDuration() {
    _controller.duration = AppMotionPolicy.duration(context, widget.duration);
    if (_controller.duration == Duration.zero) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(AppContentReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateDuration();
    if (widget.transitionKey == oldWidget.transitionKey ||
        _controller.duration == Duration.zero) {
      return;
    }
    _controller.forward(from: _controller.isAnimating ? _controller.value : 0);
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offset = AppMotionPolicy.reduceMotion(context)
        ? Offset.zero
        : widget.offset;
    // Keep an opaque stage beneath the reveal; otherwise replacing a branch
    // can briefly expose the canvas/background behind its faded scaffold.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: FadeTransition(
        opacity: _opacity,
        alwaysIncludeSemantics: true,
        child: AnimatedBuilder(
          animation: _opacity,
          builder: (context, child) => Transform.translate(
            offset: offset * (1 - _opacity.value),
            child: child,
          ),
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}
