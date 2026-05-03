import 'package:flutter/material.dart';

import '../tokens/motion_tokens.dart';

/// Wraps a [FloatingActionButton] so it slides out of view when the user
/// scrolls down and reappears when they scroll up.
///
/// Place this widget as the [Scaffold.floatingActionButton]. It listens
/// to [ScrollNotification]s bubbling up from the scaffold body.
class ScrollAwareFab extends StatefulWidget {
  const ScrollAwareFab({super.key, required this.child});

  final Widget child;

  @override
  State<ScrollAwareFab> createState() => _ScrollAwareFabState();
}

class _ScrollAwareFabState extends State<ScrollAwareFab> {
  bool _visible = true;

  bool _onNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    // Ignore overscroll (e.g. bouncing at list boundaries).
    if (notification.metrics.outOfRange) return false;

    final delta = notification.scrollDelta ?? 0;

    // Scrolling down → hide; scrolling up → show.
    if (delta > 0 && !_visible) return false;
    if (delta < 0 && _visible) return false;

    if (delta > 0 && notification.metrics.pixels > 0) {
      setState(() => _visible = false);
    } else if (delta < 0) {
      setState(() => _visible = true);
    }
    return false; // Don't consume the notification.
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 2),
        duration: Motion.medium,
        curve: _visible ? Motion.emphasizedDecelerate : Motion.standardAccelerate,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: Motion.medium,
          curve: _visible ? Motion.emphasizedDecelerate : Motion.standardAccelerate,
          child: widget.child,
        ),
      ),
    );
  }
}
