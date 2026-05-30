import 'package:flutter/widgets.dart';

import 'back_navigation.dart';

/// Gives a full-canvas route that lives **outside the dock shell** the
/// same Android system-back safety net the shell provides via its own
/// `PopScope` (`app/app_dock_shell.dart`).
///
/// The dock shell is the only place that handles the root system-back
/// gesture. Routes mounted as its siblings (the Settings subtree, …)
/// therefore have *no* system-back handler: when one of them is the
/// navigation-stack root — reached via `go()`, a deep link, or app
/// restoration — `GoRouter.canPop()` is `false`, so the back gesture
/// falls through to the OS and exits the app. The toolbar back arrow
/// escapes this because [smartPop] falls back to `go(logicalParent)`;
/// this widget makes the system gesture behave identically.
///
/// Wrap the page content (not tab roots — those intentionally exit /
/// switch tabs). [fallback] mirrors [smartPop]'s: the route to land on
/// when there is no back stack at all; defaults to the [logicalParentOf]
/// the current location.
class SystemBackScope extends StatelessWidget {
  const SystemBackScope({super.key, required this.child, this.fallback});

  final Widget child;
  final String? fallback;

  @override
  Widget build(BuildContext context) {
    // canPop:false so the gesture always routes through [smartPop], which
    // pops when it can and otherwise navigates to the logical parent —
    // matching the dock shell's PopScope contract and the back arrow.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        smartPop(context, fallback: fallback);
      },
      child: child,
    );
  }
}
