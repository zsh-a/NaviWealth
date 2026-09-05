import 'package:flutter/material.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// Reveals content without removing the outgoing body before its fade ends.
/// Hidden content is removed after the transition and cannot receive input
/// or accessibility focus while collapsing.
class AnimatedSizeFade extends StatelessWidget {
  const AnimatedSizeFade({
    super.key,
    required this.visible,
    required this.child,
    this.duration = Motion.medium,
    this.curve = Motion.standard,
    this.alignment = Alignment.topCenter,
  });

  final bool visible;
  final Widget child;
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = AppMotionPolicy.duration(context, duration);
    return ExcludeFocus(
      excluding: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedSwitcher(
            duration: effectiveDuration,
            reverseDuration: effectiveDuration,
            switchInCurve: curve,
            switchOutCurve: curve,
            layoutBuilder: (current, previous) => Stack(
              alignment: alignment.resolve(Directionality.of(context)),
              children: [
                for (final outgoing in previous)
                  ExcludeFocus(
                    child: ExcludeSemantics(
                      child: IgnorePointer(child: outgoing),
                    ),
                  ),
                ?current,
              ],
            ),
            transitionBuilder: (child, animation) {
              final faded = FadeTransition(opacity: animation, child: child);
              if (AppMotionPolicy.reduceMotion(context)) return faded;
              return SizeTransition(
                sizeFactor: animation,
                alignment: alignment,
                child: faded,
              );
            },
            child: visible
                ? KeyedSubtree(key: const ValueKey('expanded'), child: child)
                : const SizedBox.shrink(key: ValueKey('collapsed')),
          ),
        ),
      ),
    );
  }
}
