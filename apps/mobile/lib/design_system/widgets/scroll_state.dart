import 'package:flutter/material.dart';

/// Tracks whether a scrollable is actively scrolling.
///
/// Used by [LiquidGlassCard] to degrade glass rendering quality during
/// scroll, eliminating per-frame BackdropFilter cost while the user is
/// swiping. Quality is restored when scrolling stops.
final ValueNotifier<bool> isScrollingNotifier = ValueNotifier(false);

/// Wraps a scrollable child and updates [isScrollingNotifier] on scroll
/// start/end. Place this directly around any [ListView], [GridView], or
/// [CustomScrollView] that contains [LiquidGlassCard] items.
class ScrollNotificationHandler extends StatelessWidget {
  const ScrollNotificationHandler({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          isScrollingNotifier.value = true;
        } else if (notification is ScrollEndNotification) {
          isScrollingNotifier.value = false;
        }
        return false;
      },
      child: child,
    );
  }
}
