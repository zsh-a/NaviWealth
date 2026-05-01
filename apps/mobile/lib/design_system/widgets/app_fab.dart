import 'package:flutter/material.dart';

import '../../core/haptics/haptics.dart';

/// [FloatingActionButton] wrapper that fires [Haptics.primaryPress] before
/// invoking the caller's `onPressed`. Use everywhere a FAB launches a primary
/// action so the app's tactile feedback stays consistent.
class AppFab extends StatelessWidget {
  /// Standard circular FAB.
  const AppFab({
    super.key,
    required this.onPressed,
    required Widget this.child,
    this.tooltip,
  })  : icon = null,
        label = null,
        _isExtended = false;

  /// Pill-shaped FAB with leading [icon] and a [label].
  const AppFab.extended({
    super.key,
    required this.onPressed,
    required Widget this.icon,
    required Widget this.label,
    this.tooltip,
  })  : child = null,
        _isExtended = true;

  final VoidCallback? onPressed;
  final Widget? child;
  final Widget? icon;
  final Widget? label;
  final String? tooltip;
  final bool _isExtended;

  @override
  Widget build(BuildContext context) {
    final wrapped = Haptics.wrapPrimary(onPressed);
    if (_isExtended) {
      return FloatingActionButton.extended(
        onPressed: wrapped,
        tooltip: tooltip,
        icon: icon,
        label: label!,
      );
    }
    return FloatingActionButton(
      onPressed: wrapped,
      tooltip: tooltip,
      child: child,
    );
  }
}
