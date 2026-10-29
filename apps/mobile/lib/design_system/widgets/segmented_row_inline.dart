part of 'segmented_row.dart';

class _InlineSegments<T> extends StatefulWidget {
  const _InlineSegments({required this.control});

  final SegmentedRow<T> control;

  @override
  State<_InlineSegments<T>> createState() => _InlineSegmentsState<T>();
}

class _InlineSegmentsState<T> extends State<_InlineSegments<T>> {
  final _nodes = <T, FocusNode>{};
  FocusNode? _focusBeforeReparent;

  SegmentedRow<T> get control => widget.control;

  @override
  void deactivate() {
    _focusBeforeReparent = _nodes.values
        .where((node) => node.hasFocus)
        .firstOrNull;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    final focused = _focusBeforeReparent;
    _focusBeforeReparent = null;
    if (focused == null) return;
    // The route survives a shell breakpoint through its GlobalKey, but moving
    // its DOM subtree clears browser focus. Restore only the previously focused
    // range once the new shell has attached and committed its semantics.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          control.onChanged != null &&
          _nodes.containsValue(focused)) {
        focused.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _InlineSegments<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final option in _nodes.keys.toList()) {
      if (!control.options.contains(option)) _nodes.remove(option)!.dispose();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusChanged() => setState(() {});

  void _select(T option) {
    if (control.onChanged == null) return;
    _nodes[option]?.requestFocus();
    if (option != control.value) control.onChanged?.call(option);
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (control.onChanged == null ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final current = control.options.indexWhere(
      (option) => _nodes[option]?.hasFocus ?? false,
    );
    if (current < 0) return KeyEventResult.ignored;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final key = event.logicalKey;
    final int next;
    if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = control.options.length - 1;
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final forward = (key == LogicalKeyboardKey.arrowRight) != rtl;
      next = (current + (forward ? 1 : -1)) % control.options.length;
    } else {
      return KeyEventResult.ignored;
    }
    final option = control.options[next];
    _nodes[option]!.requestFocus();
    if (option != control.value) {
      // Arrow selection bypasses AppTappable's Enter/Space/tap callback.
      AppInteraction.signal(AppInteractionIntent.select);
      _select(option);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = control.onChanged != null;
    final tabStop = control.options.contains(control.value)
        ? control.value
        : control.options.first;
    for (final option in control.options) {
      final node = _nodes.putIfAbsent(
        option,
        () => FocusNode()..addListener(_focusChanged),
      );
      node.skipTraversal = option != tabStop;
    }
    final type = context.appTheme.type;
    final selectedStyle = type.numericCaptionStrong;
    final style = type.numericCaption;
    // Measure both weights so selecting a different range never moves labels.
    var width = math.max(
      control.minSegmentWidth,
      AppControlHeights.touchTarget,
    );
    for (final option in control.options) {
      for (final textStyle in [style, selectedStyle]) {
        final painter = TextPainter(
          text: TextSpan(text: control.labelOf(option), style: textStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: 1,
        )..layout();
        width = math.max(width, painter.width.ceilToDouble() + AppSpacing.s24);
        painter.dispose();
      }
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = AppSpacing.s4;
            final count = control.options.length;
            final maxWidth = constraints.maxWidth;
            final maxColumns = maxWidth.isFinite
                ? ((maxWidth + gap) / (width + gap)).floor().clamp(1, count)
                : count;
            final rows = (count / maxColumns).ceil();
            final columns = (count / rows).ceil();
            final itemWidth = maxWidth.isFinite
                ? math.min(width, (maxWidth - gap * (columns - 1)) / columns)
                : width;
            // Keep the same hierarchy and keys when wrapping so a focused
            // control survives resizing and dynamic text changes.
            return Align(
              heightFactor: 1,
              child: SizedBox(
                width: itemWidth * columns + gap * (columns - 1),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final option in control.options)
                      SizedBox(
                        key: ValueKey(option),
                        width: itemWidth,
                        child: _segment(context, option, enabled: enabled),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, T option, {required bool enabled}) {
    final selected = option == control.value;
    final colors = context.theme.colors;
    final tone = selected ? colors.primary : colors.mutedForeground;
    final color = enabled ? tone : tone.withValues(alpha: AppOpacity.disabled);
    final style = selected
        ? context.appTheme.type.numericCaptionStrong
        : context.appTheme.type.numericCaption;
    final node = _nodes[option]!;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      focusable: enabled,
      focused: enabled && node.hasFocus,
      // The explicit label replaces descendant semantics, so also bridge
      // browser/accessibility focus back into Flutter's keyboard focus tree.
      onFocus: enabled ? node.requestFocus : null,
      label: control.semanticLabelOf?.call(option) ?? control.labelOf(option),
      onTap: AppInteraction.wrap(
        enabled ? () => _select(option) : null,
        intent: AppInteractionIntent.select,
      ),
      excludeSemantics: true,
      child: AppTappable(
        selected: selected,
        focusNode: node,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onPress: enabled ? () => _select(option) : null,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppControlHeights.touchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: AppMotionPolicy.duration(
                  context,
                  Motion.fast,
                  role: AppMotionRole.decorative,
                ),
                curve: Motion.standard,
                style: style.copyWith(color: color),
                child: Text(
                  control.labelOf(option),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              AppSelectionIndicator(
                selected: selected,
                length: AppSpacing.s16,
                thickness: AppSpacing.s2,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
