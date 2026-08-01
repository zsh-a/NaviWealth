part of 'agent_result_card.dart';

typedef _AgentResultEntryBuilder =
    Widget Function(agent_providers.AgentResultEntry entry);

class _SwipeableAgentResultStack extends StatefulWidget {
  const _SwipeableAgentResultStack({
    required this.entries,
    required this.entryBuilder,
  });

  final List<agent_providers.AgentResultEntry> entries;
  final _AgentResultEntryBuilder entryBuilder;

  @override
  State<_SwipeableAgentResultStack> createState() =>
      _SwipeableAgentResultStackState();
}

class _SwipeableAgentResultStackState extends State<_SwipeableAgentResultStack>
    with SingleTickerProviderStateMixin {
  static const double _switchThreshold = 48;
  static const double _velocityThreshold = 450;
  static const double _maxDragOffset = 96;

  late String _activeAgentId = widget.entries.first.agentId;
  late final AnimationController _motionController;
  double _dragOffset = 0;
  bool _settling = false;

  int get _activeIndex {
    final index = widget.entries.indexWhere(
      (entry) => entry.agentId == _activeAgentId,
    );
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController.unbounded(vsync: this)
      ..addListener(_handleMotionTick);
  }

  void _handleMotionTick() {
    if (!mounted) return;
    setState(() => _dragOffset = _motionController.value);
  }

  @override
  void dispose() {
    _motionController
      ..removeListener(_handleMotionTick)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SwipeableAgentResultStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final leadingChanged =
        oldWidget.entries.first.agentId != widget.entries.first.agentId;
    final activeStillExists = widget.entries.any(
      (entry) => entry.agentId == _activeAgentId,
    );
    if (leadingChanged || !activeStillExists) {
      _motionController.stop();
      _activeAgentId = widget.entries.first.agentId;
      _dragOffset = 0;
      _motionController.value = 0;
      _settling = false;
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (_settling) return;
    _motionController.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_settling) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx)
          .clamp(-_maxDragOffset, _maxDragOffset)
          .toDouble();
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_settling) return;
    final velocity = details.primaryVelocity ?? 0;
    final shouldSwitch =
        _dragOffset.abs() >= _switchThreshold ||
        velocity.abs() >= _velocityThreshold;
    if (!shouldSwitch) {
      unawaited(_animateBack());
      return;
    }
    final direction = _dragOffset != 0 ? _dragOffset.sign : velocity.sign;
    unawaited(
      _switchCard(step: direction < 0 ? 1 : -1, exitDirection: direction),
    );
  }

  void _onDragCancel() {
    if (_settling) return;
    unawaited(_animateBack());
  }

  Future<void> _animateBack() async {
    setState(() => _settling = true);
    final duration = AppMotionPolicy.duration(context, Motion.medium);
    final completed = await _animateOffset(
      0,
      duration: duration,
      curve: Motion.standardDecelerate,
    );
    if (mounted && completed) setState(() => _settling = false);
  }

  Future<void> _switchCard({
    required int step,
    required double exitDirection,
  }) async {
    setState(() => _settling = true);
    final renderBox = context.findRenderObject();
    final measuredWidth = renderBox is RenderBox ? renderBox.size.width : 0.0;
    final fallbackWidth = MediaQuery.sizeOf(context).width;
    final deckWidth = measuredWidth > 0 ? measuredWidth : fallbackWidth;
    final exitTarget = exitDirection * deckWidth * 0.92;
    final exited = await _animateOffset(
      exitTarget,
      duration: AppMotionPolicy.duration(context, Motion.fast),
      curve: Motion.standardAccelerate,
    );
    if (!mounted || !exited) return;

    final nextIndex = (_activeIndex + step) % widget.entries.length;
    final incomingOffset = -exitDirection * AppSpacing.s48;
    setState(() {
      _activeAgentId = widget.entries[nextIndex].agentId;
      _dragOffset = incomingOffset;
    });
    _motionController.value = incomingOffset;
    final entered = await _animateOffset(
      0,
      duration: AppMotionPolicy.duration(context, Motion.medium),
      curve: Motion.standardDecelerate,
    );
    if (mounted && entered) setState(() => _settling = false);
  }

  Future<bool> _animateOffset(
    double target, {
    required Duration duration,
    required Curve curve,
  }) async {
    if (duration == Duration.zero) {
      _motionController.value = target;
      return true;
    }
    _motionController.value = _dragOffset;
    try {
      await _motionController
          .animateTo(target, duration: duration, curve: curve)
          .orCancel;
      return true;
    } on TickerCanceled {
      // A new data snapshot or disposal superseded this motion.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.entries[_activeIndex];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final revealProgress = (_dragOffset.abs() / _maxDragOffset)
            .clamp(0.0, 1.0)
            .toDouble();
        final exitProgress = (_dragOffset.abs() / (width * 0.92))
            .clamp(0.0, 1.0)
            .toDouble();
        final rotation = width == 0 ? 0.0 : (_dragOffset / width) * 0.035;
        final opacity = (1 - exitProgress * exitProgress)
            .clamp(0.0, 1.0)
            .toDouble();
        double lerp(double from, double to) =>
            from + (to - from) * revealProgress;

        return Stack(
          key: const ValueKey<String>('agent-result-stack'),
          children: [
            Positioned.fill(
              left: lerp(AppSpacing.s12, AppSpacing.s6),
              right: lerp(AppSpacing.s12, AppSpacing.s6),
              top: lerp(AppSpacing.s16, AppSpacing.s8),
              bottom: lerp(0, AppSpacing.s8),
              child: const _AgentResultBackplate(level: 2),
            ),
            Positioned.fill(
              left: lerp(AppSpacing.s6, 0),
              right: lerp(AppSpacing.s6, 0),
              top: lerp(AppSpacing.s8, 0),
              bottom: lerp(AppSpacing.s8, AppSpacing.s16),
              child: const _AgentResultBackplate(level: 1),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s16),
              child: GestureDetector(
                key: const ValueKey<String>('agent-result-front-card'),
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _onDragCancel,
                child: Opacity(
                  opacity: opacity,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.translationValues(_dragOffset, 0, 0)
                      ..rotateZ(rotation),
                    child: KeyedSubtree(
                      key: ValueKey<String>(active.agentId),
                      child: widget.entryBuilder(active),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.s4,
              child: _AgentResultPageIndicator(
                count: widget.entries.length,
                activeIndex: _activeIndex,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AgentResultBackplate extends StatelessWidget {
  const _AgentResultBackplate({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colors.muted.withValues(
              alpha: level == 1 ? AppOpacity.subtle : AppOpacity.faint,
            ),
            colors.card,
          ),
          border: Border.all(
            color: colors.border.withValues(alpha: AppOpacity.highlight),
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}

class _AgentResultPageIndicator extends StatelessWidget {
  const _AgentResultPageIndicator({
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final duration = AppMotionPolicy.duration(context, Motion.fast);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++) ...[
          AnimatedContainer(
            duration: duration,
            curve: Motion.standardDecelerate,
            width: index == activeIndex ? AppSpacing.s12 : AppSpacing.s4,
            height: AppSpacing.s4,
            decoration: BoxDecoration(
              color: index == activeIndex ? colors.primary : colors.border,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          if (index != count - 1) const SizedBox(width: AppSpacing.s4),
        ],
      ],
    );
  }
}
