import 'package:flutter/widgets.dart';

import '../tokens/motion_tokens.dart';
import 'fade_slide_in.dart';

/// A [Column] that staggers its children's entrance animations.
///
/// Each child is wrapped in a [FadeSlideIn] with an incrementing delay.
/// The total stagger duration is capped at [maxTotalDelay] — if the
/// computed total exceeds the cap, delays are compressed proportionally
/// so the last child still enters within the budget.
///
/// This prevents long lists from looking like items are still trickling
/// in seconds after the page loaded.
///
/// ```dart
/// StaggeredColumn(
///   children: items.map((item) => ItemCard(item)).toList(),
/// )
/// ```
///
/// The animation respects [MediaQueryData.disableAnimations] via
/// [FadeSlideIn].
class StaggeredColumn extends StatelessWidget {
  const StaggeredColumn({
    super.key,
    required this.children,
    this.staggerDelay = Motion.staggerStep,
    this.maxTotalDelay = Motion.staggerBudget,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.min,
  });

  final List<Widget> children;

  /// Delay between each child's entrance.
  final Duration staggerDelay;

  /// Maximum total stagger duration. If `children.length * staggerDelay`
  /// exceeds this, delays are scaled down proportionally.
  final Duration maxTotalDelay;

  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      children: [
        for (var i = 0; i < children.length; i++)
          FadeSlideIn(
            delay: Motion.staggerDelayFor(
              i,
              children.length,
              step: staggerDelay,
              budget: maxTotalDelay,
            ),
            child: children[i],
          ),
      ],
    );
  }
}
