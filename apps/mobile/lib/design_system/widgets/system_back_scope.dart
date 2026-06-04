import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';
import 'app_toast.dart';
import 'back_navigation.dart';

typedef SystemBackHandler = bool Function(BuildContext context);

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

/// Intercepts a root-level system back gesture and requires a second back
/// within [exitWindow] before leaving the app.
///
/// [onBack] can handle app-specific back behavior first (for example:
/// pop a route, jump from another primary tab to Home, clear a selected
/// detail). Returning `true` consumes the gesture and disarms any pending
/// exit confirmation. Returning `false` falls through to the exit arm.
class ExitConfirmingSystemBackScope extends StatefulWidget {
  const ExitConfirmingSystemBackScope({
    super.key,
    required this.child,
    this.onBack,
    this.disarmKey,
    this.exitWindow = const Duration(seconds: 2),
  });

  final Widget child;
  final SystemBackHandler? onBack;
  final Object? disarmKey;
  final Duration exitWindow;

  @override
  State<ExitConfirmingSystemBackScope> createState() =>
      _ExitConfirmingSystemBackScopeState();
}

class _ExitConfirmingSystemBackScopeState
    extends State<ExitConfirmingSystemBackScope> {
  bool _exitArmed = false;
  Timer? _exitResetTimer;

  @override
  void didUpdateWidget(ExitConfirmingSystemBackScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disarmKey != oldWidget.disarmKey) {
      _disarmExit();
    }
  }

  @override
  void dispose() {
    _exitResetTimer?.cancel();
    super.dispose();
  }

  void _disarmExit() {
    _exitResetTimer?.cancel();
    _exitArmed = false;
  }

  void _onSystemBack(bool didPop) {
    if (didPop) return;
    if (widget.onBack?.call(context) ?? false) {
      _disarmExit();
      return;
    }
    if (_exitArmed) {
      _exitResetTimer?.cancel();
      SystemNavigator.pop();
      return;
    }
    _exitArmed = true;
    AppMessenger.show(
      context,
      ToastKind.info,
      AppLocalizations.of(context).pressBackAgainToExit,
      duration: widget.exitWindow,
    );
    _exitResetTimer?.cancel();
    _exitResetTimer = Timer(widget.exitWindow, () {
      if (mounted) _exitArmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onSystemBack(didPop),
      child: Listener(
        onPointerDown: (_) {
          if (_exitArmed) _disarmExit();
        },
        child: widget.child,
      ),
    );
  }
}
