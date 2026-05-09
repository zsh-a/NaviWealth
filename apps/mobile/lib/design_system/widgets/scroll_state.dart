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

/// App-wide scope that publishes [isScrollingNotifier]'s value via an
/// [InheritedWidget].
///
/// Place once near the app root; descendant glass surfaces read the value
/// with [ScrollingScope.of] instead of subscribing to the notifier
/// individually. With N glass cards this collapses N
/// `ValueListenableBuilder` subscriptions into a single root-level
/// `ListenableBuilder` plus standard InheritedWidget dependency tracking.
class ScrollingScope extends StatelessWidget {
  const ScrollingScope({super.key, required this.child});

  final Widget child;

  /// The current scrolling state. Returns `false` when called outside any
  /// [ScrollingScope] (e.g. detached test harnesses).
  static bool of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_InheritedScrollingState>();
    return inherited?.isScrolling ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: isScrollingNotifier,
      builder: (ctx, inner) => _InheritedScrollingState(
        isScrolling: isScrollingNotifier.value,
        child: inner!,
      ),
      child: child,
    );
  }
}

class _InheritedScrollingState extends InheritedWidget {
  const _InheritedScrollingState({
    required this.isScrolling,
    required super.child,
  });

  final bool isScrolling;

  @override
  bool updateShouldNotify(_InheritedScrollingState old) =>
      old.isScrolling != isScrolling;
}
