import 'package:flutter/material.dart';

import '../../core/haptics/haptics.dart';

/// [Dismissible] wrapper that fires [Haptics.destructive] when the user
/// commits a swipe that deletes / archives the underlying tile. Suitable for
/// list rows that surface a destructive secondary action via swipe.
///
/// The haptic fires the moment the swipe gesture is committed (right before
/// the caller's `confirmDismiss` / `onDismissed` runs), so the user feels the
/// bump regardless of whether the dismissal is synchronous or guarded behind
/// an async confirmation step.
class AppDismissibleListTile extends StatelessWidget {
  const AppDismissibleListTile({
    super.key,
    required this.dismissibleKey,
    required this.child,
    this.background,
    this.secondaryBackground,
    this.direction = DismissDirection.horizontal,
    this.confirmDismiss,
    this.onDismissed,
  });

  final Key dismissibleKey;
  final Widget child;
  final Widget? background;
  final Widget? secondaryBackground;
  final DismissDirection direction;
  final ConfirmDismissCallback? confirmDismiss;
  final DismissDirectionCallback? onDismissed;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: dismissibleKey,
      direction: direction,
      background: background,
      secondaryBackground: secondaryBackground,
      confirmDismiss: confirmDismiss == null
          ? null
          : (dir) {
              Haptics.destructive();
              return confirmDismiss!(dir);
            },
      onDismissed: onDismissed == null
          ? null
          : (dir) {
              if (confirmDismiss == null) {
                Haptics.destructive();
              }
              onDismissed!(dir);
            },
      child: child,
    );
  }
}
