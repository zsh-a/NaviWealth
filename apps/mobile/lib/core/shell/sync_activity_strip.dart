import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../sync/providers.dart';
import '../sync/sync_status.dart';

/// Shell-level sync activity indicator (doc 11 触发器 "完成同步").
///
/// A hairline strip pinned to the top of every layout:
/// * while a sync cycle is in flight — an indeterminate brand-colored
///   segment sweeps the width;
/// * on completion — the full strip flashes success and fades out;
/// * on a failed cycle — one danger flash (the persistent story lives on
///   the sync status page, not here).
///
/// Idle/online steady states render nothing: the strip only speaks when
/// something changed, so it never competes with content.
class SyncActivityStrip extends ConsumerStatefulWidget {
  const SyncActivityStrip({super.key});

  @override
  ConsumerState<SyncActivityStrip> createState() => _SyncActivityStripState();
}

enum _StripPhase { none, active, done, error }

class _SyncActivityStripState extends ConsumerState<SyncActivityStrip> {
  _StripPhase _phase = _StripPhase.none;
  SyncStatus? _last;

  void _onEvent(SyncStatusEvent event) {
    final previous = _last;
    _last = event.status;
    final next = switch (event.status) {
      SyncStatus.syncing => _StripPhase.active,
      SyncStatus.online when previous == SyncStatus.syncing => _StripPhase.done,
      SyncStatus.failed when previous == SyncStatus.syncing =>
        _StripPhase.error,
      _ => _StripPhase.none,
    };
    if (next != _phase) {
      setState(() => _phase = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SyncStatusEvent>>(syncStatusEventStreamProvider, (
      _,
      value,
    ) {
      final event = value.value;
      if (event != null) _onEvent(event);
    });

    final colors = context.theme.colors;
    return IgnorePointer(
      child: SizedBox(
        height: AppStroke.branch,
        child: switch (_phase) {
          _StripPhase.none => const SizedBox.shrink(),
          _StripPhase.active => _IndeterminateBar(color: colors.primary),
          _StripPhase.done => _CompletionFlash(
            color: context.appTheme.status.success.fg,
            onDone: () {
              if (mounted) setState(() => _phase = _StripPhase.none);
            },
          ),
          _StripPhase.error => _CompletionFlash(
            color: context.appTheme.status.danger.fg,
            onDone: () {
              if (mounted) setState(() => _phase = _StripPhase.none);
            },
          ),
        },
      ),
    );
  }
}

/// Sweeping indeterminate segment. Under reduce-motion the strip renders as
/// a static line — activity is still visible, nothing moves.
class _IndeterminateBar extends StatefulWidget {
  const _IndeterminateBar({required this.color});

  final Color color;

  @override
  State<_IndeterminateBar> createState() => _IndeterminateBarState();
}

class _IndeterminateBarState extends State<_IndeterminateBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.typingCycle,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotionPolicy.isEnabled(context, role: AppMotionRole.status)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppMotionPolicy.isEnabled(context, role: AppMotionRole.status)) {
      return ColoredBox(
        color: widget.color.withValues(alpha: AppOpacity.prominent),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final segment = width * 0.3;
          final x = (width + segment) * _controller.value - segment;
          return Stack(
            children: [
              ColoredBox(
                color: widget.color.withValues(alpha: AppOpacity.light),
                child: const SizedBox.expand(),
              ),
              Positioned(
                left: x,
                width: segment,
                top: 0,
                bottom: 0,
                child: ColoredBox(color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Full-width flash that fades out, then reports completion.
class _CompletionFlash extends StatelessWidget {
  const _CompletionFlash({required this.color, required this.onDone});

  final Color color;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: AppMotionPolicy.duration(
        context,
        Motion.ticker,
        role: AppMotionRole.status,
      ),
      curve: Motion.standardDecelerate,
      onEnd: onDone,
      builder: (context, opacity, _) => Opacity(
        opacity: opacity,
        child: ColoredBox(color: color, child: const SizedBox.expand()),
      ),
    );
  }
}
