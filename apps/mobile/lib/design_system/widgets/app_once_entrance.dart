import 'package:flutter/widgets.dart';

import '../tokens/app_motion_policy.dart';
import 'app_entrance.dart';

/// Registry that remembers which list indices have already been revealed
/// during a list's current mount.
///
/// `ListView` / `GridView` recycle item subtrees as they scroll out of and
/// back into view, so naively wrapping an `itemBuilder` child in
/// [AppEntrance] replays the entrance every time an item re-enters the
/// viewport. The tracker records the highest index ever built; only items
/// beyond that watermark are allowed to animate, so recycled rows render
/// statically while genuinely new content (pagination, insertions) still
/// flows in.
class AppEntranceTracker {
  int _maxRevealedIndex = -1;

  /// The highest item index that has already been revealed.
  int get maxRevealedIndex => _maxRevealedIndex;

  /// Returns `true` exactly once per [index]: the first time an item at or
  /// beyond the current watermark is built.
  bool shouldAnimate(int index) {
    if (index <= _maxRevealedIndex) return false;
    _maxRevealedIndex = index;
    return true;
  }
}

/// Provides an [AppEntranceTracker] to descendant [AppOnceEntrance] items.
///
/// Place the scope *above* any loading/data branch (`AsyncValue.when`,
/// `StreamBuilder`, …) of the list so the tracker survives skeleton ↔ content
/// remounts — pull-to-refresh then reuses the same tracker and the entrance
/// does not replay:
///
/// ```dart
/// AppEntranceScope(
///   child: itemsAsync.when(
///     loading: () => const AppListPageSkeleton(itemCount: 5),
///     data: (items) => ListView.builder(
///       itemCount: items.length,
///       itemBuilder: (context, i) =>
///           AppOnceEntrance(index: i, child: ItemCard(items[i])),
///     ),
///   ),
/// )
/// ```
class AppEntranceScope extends StatefulWidget {
  const AppEntranceScope({required this.child, super.key});

  final Widget child;

  /// The nearest tracker above [context], if any. Does not register a
  /// dependency — items read it once when they are first built.
  static AppEntranceTracker? maybeTrackerOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<_AppEntranceScopeData>();
    final data = element?.widget;
    return data is _AppEntranceScopeData ? data.tracker : null;
  }

  @override
  State<AppEntranceScope> createState() => _AppEntranceScopeState();
}

class _AppEntranceScopeState extends State<AppEntranceScope> {
  final AppEntranceTracker tracker = AppEntranceTracker();

  @override
  Widget build(BuildContext context) {
    return _AppEntranceScopeData(tracker: tracker, child: widget.child);
  }
}

class _AppEntranceScopeData extends InheritedWidget {
  const _AppEntranceScopeData({required this.tracker, required super.child});

  final AppEntranceTracker tracker;

  @override
  bool updateShouldNotify(_AppEntranceScopeData oldWidget) => false;
}

/// An [AppEntrance] that plays only the first time an item at [index]
/// appears in the enclosing [AppEntranceScope].
///
/// Use in `itemBuilder`s of recycling lists to get a one-shot entrance
/// without scroll-back replays. The decision is made once when the item
/// subtree is first built; afterwards the child renders statically even if
/// the list recycles or rebuilds it.
///
/// Outside an [AppEntranceScope] this degrades to a plain [AppEntrance]
/// (animates on every mount).
///
/// The entrance uses [AppMotionRole.decorative], so reduce-motion users get
/// no animation at all.
class AppOnceEntrance extends StatefulWidget {
  const AppOnceEntrance({
    required this.index,
    required this.child,
    super.key,
    this.slideDistance = 8,
  });

  /// Item position in the list. Indices at or below the scope's revealed
  /// watermark render without animation.
  final int index;

  final Widget child;

  /// Forwarded to [AppEntrance.slideDistance]. → 8
  final double slideDistance;

  @override
  State<AppOnceEntrance> createState() => _AppOnceEntranceState();
}

class _AppOnceEntranceState extends State<AppOnceEntrance> {
  late final bool _animate;

  @override
  void initState() {
    super.initState();
    final tracker = AppEntranceScope.maybeTrackerOf(context);
    _animate = tracker?.shouldAnimate(widget.index) ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return AppEntrance(
      enabled: _animate,
      role: AppMotionRole.decorative,
      slideDistance: widget.slideDistance,
      child: widget.child,
    );
  }
}
