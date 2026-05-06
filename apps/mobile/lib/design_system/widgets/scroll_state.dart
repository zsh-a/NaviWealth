import 'dart:async';

import 'package:flutter/material.dart';

/// Tracks whether a scrollable is actively scrolling.
///
/// Used by [LiquidGlassCard] to degrade glass rendering quality during
/// scroll, eliminating per-frame BackdropFilter cost while the user is
/// swiping. Quality is restored when scrolling stops.
final ValueNotifier<bool> isScrollingNotifier = ValueNotifier(false);
Timer? _scrollEndDebounce;

void _setScrolling(bool value) {
  if (value) {
    _scrollEndDebounce?.cancel();
    _scrollEndDebounce = null;
    if (!isScrollingNotifier.value) {
      isScrollingNotifier.value = true;
    }
    return;
  }
  _scrollEndDebounce?.cancel();
  _scrollEndDebounce = Timer(const Duration(milliseconds: 120), () {
    if (isScrollingNotifier.value) {
      isScrollingNotifier.value = false;
    }
  });
}

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
          _setScrolling(true);
        } else if (notification is ScrollEndNotification) {
          _setScrolling(false);
        }
        return false;
      },
      child: child,
    );
  }
}
