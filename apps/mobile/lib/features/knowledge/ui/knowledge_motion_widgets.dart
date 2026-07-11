part of '_widgets.dart';

const Duration _kKnowledgeFloatingActionMotionDuration = Motion.medium;

/// Mixin for pages that hide/show a FAB on scroll direction.
///
/// Provides [fabHidden] and [onScrollUpdate]. The concrete [State] must
/// call [onScrollUpdate] from a [NotificationListener<ScrollUpdateNotification>]
/// and pass [fabHidden] to [KnowledgeFloatingActionMotion.hidden].
mixin KnowledgeFabScrollHideMixin<T extends StatefulWidget> on State<T> {
  bool fabHidden = false;

  bool onScrollUpdate(ScrollUpdateNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final delta = notification.scrollDelta ?? 0;
    if (delta > 4 && !fabHidden) {
      setState(() => fabHidden = true);
    } else if (delta < -4 && fabHidden) {
      setState(() => fabHidden = false);
    }
    return false;
  }
}

/// Shared hide/show motion for KnowledgeOS floating create actions.
class KnowledgeFloatingActionMotion extends StatelessWidget {
  const KnowledgeFloatingActionMotion({
    super.key,
    required this.hidden,
    required this.child,
  });

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: hidden,
      child: AnimatedSlide(
        duration: AppMotionPolicy.duration(
          context,
          _kKnowledgeFloatingActionMotionDuration,
        ),
        curve: Motion.standardDecelerate,
        offset: hidden ? const Offset(0, 1.25) : Offset.zero,
        child: AnimatedOpacity(
          duration: AppMotionPolicy.duration(
            context,
            _kKnowledgeFloatingActionMotionDuration,
          ),
          curve: Motion.standardDecelerate,
          opacity: hidden ? 0 : 1,
          child: child,
        ),
      ),
    );
  }
}

/// Pull-to-refresh wrapper with Forui [FProgress] indicator.
///
/// Uses [NotificationListener] to track overscroll drag and triggers
/// [onRefresh] when the drag exceeds the threshold. The indicator
/// scales in from the top as the user pulls.
const double _kRefreshTriggerExtent = 80;

class KnowledgePullToRefresh extends StatefulWidget {
  const KnowledgePullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<KnowledgePullToRefresh> createState() => _KnowledgePullToRefreshState();
}

class _KnowledgePullToRefreshState extends State<KnowledgePullToRefresh> {
  double _dragExtent = 0;
  bool _refreshing = false;

  bool _onNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        metrics.pixels <= metrics.minScrollExtent) {
      final delta = notification.scrollDelta ?? 0;
      if (delta < 0) {
        setState(() {
          _dragExtent = (_dragExtent - delta).clamp(0, _kRefreshTriggerExtent);
        });
      }
    }

    if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        notification.overscroll < 0) {
      setState(() {
        _dragExtent = (_dragExtent - notification.overscroll).clamp(
          0,
          _kRefreshTriggerExtent,
        );
      });
    }

    if (notification is ScrollEndNotification) {
      if (_dragExtent >= _kRefreshTriggerExtent && !_refreshing) {
        _refresh();
      } else if (!_refreshing && _dragExtent != 0) {
        setState(() => _dragExtent = 0);
      }
    }
    return false;
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _dragExtent = _kRefreshTriggerExtent;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _dragExtent = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _refreshing || _dragExtent > 0;
    final progress = (_dragExtent / _kRefreshTriggerExtent).clamp(0.0, 1.0);
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onNotification,
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: AppMotionPolicy.duration(context, Motion.fast),
              opacity: visible ? 1 : 0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s12),
                  child: Transform.scale(
                    scale: _refreshing ? 1 : progress,
                    child: const FCircularProgress(
                      size: FCircularProgressSizeVariant.xs,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
