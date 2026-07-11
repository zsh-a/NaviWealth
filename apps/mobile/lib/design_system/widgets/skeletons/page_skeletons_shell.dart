part of 'page_skeletons.dart';

/// Minimum visible time for a page-level skeleton. Shorter than this and
/// the human eye reads the swap as a flash rather than a hand-off.
const Duration _kMinSkeletonDisplay = Motion.fast;

/// Wraps an async builder so the skeleton phase is held for at least
/// [minDisplay] before the resolved widget swaps in. The data widget is
/// re-built on every frame once data is available; the shell only gates
/// the visibility of the skeleton itself.
class PageSkeletonShell<T> extends StatefulWidget {
  const PageSkeletonShell({
    super.key,
    required this.skeleton,
    required this.isLoading,
    required this.child,
    this.minDisplay = _kMinSkeletonDisplay,
  });

  /// Skeleton template to show while [isLoading] is true (or before
  /// [minDisplay] has elapsed).
  final Widget skeleton;

  /// Whether the underlying provider is still loading.
  final bool isLoading;

  /// Real content. Only shown once both [isLoading] is false and the
  /// minimum skeleton-display window has elapsed.
  final Widget child;

  /// Lower bound on how long the skeleton stays on screen. Defaults to
  /// 120ms: short enough not to feel slow, long enough not to flash.
  final Duration minDisplay;

  @override
  State<PageSkeletonShell<T>> createState() => _PageSkeletonShellState<T>();
}

class _PageSkeletonShellState<T> extends State<PageSkeletonShell<T>> {
  bool _minElapsed = false;

  @override
  void initState() {
    super.initState();
    _scheduleElapsed();
  }

  void _scheduleElapsed() {
    Future<void>.delayed(widget.minDisplay).then((_) {
      if (!mounted) return;
      setState(() => _minElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showSkeleton = widget.isLoading || !_minElapsed;
    return AnimatedSwitcher(
      duration: AppMotionPolicy.duration(context, Motion.fast),
      child: showSkeleton
          ? KeyedSubtree(
              key: const ValueKey('page-skeleton'),
              child: widget.skeleton,
            )
          : KeyedSubtree(key: const ValueKey('page-data'), child: widget.child),
    );
  }
}
