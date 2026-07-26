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
