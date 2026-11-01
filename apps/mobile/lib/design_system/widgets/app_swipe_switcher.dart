import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import '../tokens/dimens_tokens.dart';
import 'app_interaction.dart';

/// Touch shortcut for adjacent page categories shown by a visible selector.
///
/// The selector and this region share one value and change callback. A release
/// switches at most one category, without wrapping or moving the foreground.
/// Descendant horizontal controls keep priority in the gesture arena. System
/// back edges and mouse selection remain available to their existing owners.
class AppSwipeSwitcher<T> extends StatefulWidget {
  const AppSwipeSwitcher({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.child,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final Widget child;

  @override
  State<AppSwipeSwitcher<T>> createState() => _AppSwipeSwitcherState<T>();
}

class _AppSwipeSwitcherState<T> extends State<AppSwipeSwitcher<T>> {
  static const _flingVelocity = 650.0;
  static const _backGestureInset = 24.0;
  int? _startIndex;
  double _distance = 0;

  @override
  void didUpdateWidget(AppSwipeSwitcher<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value ||
        !listEquals(widget.options, oldWidget.options) ||
        widget.onChanged == null) {
      _cancel();
    }
  }

  bool _shouldAccept(PointerEvent event) {
    final media = MediaQuery.of(context);
    var left = media.systemGestureInsets.left;
    var right = media.systemGestureInsets.right;
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      if (Directionality.of(context) == TextDirection.ltr) {
        if (left < _backGestureInset) left = _backGestureInset;
      } else if (right < _backGestureInset) {
        right = _backGestureInset;
      }
    }
    return event.position.dx > left &&
        event.position.dx < media.size.width - right;
  }

  void _start(DragStartDetails details) {
    _startIndex = widget.options.indexOf(widget.value);
    _distance = 0;
  }

  void _update(DragUpdateDetails details) {
    _distance += details.primaryDelta ?? 0;
  }

  void _end(DragEndDetails details) {
    final index = _startIndex;
    final distance = _distance;
    _cancel();
    if (index == null || index < 0 || widget.onChanged == null) return;
    final velocity = details.primaryVelocity ?? 0;
    final fling =
        distance.abs() >= kTouchSlop &&
        velocity.abs() >= _flingVelocity &&
        velocity * distance > 0;
    if (distance.abs() < AppSpacing.s48 && !fling) return;
    final forward = Directionality.of(context) == TextDirection.ltr
        ? distance < 0
        : distance > 0;
    final next = index + (forward ? 1 : -1);
    if (next < 0 || next >= widget.options.length) return;
    AppInteraction.signal(AppInteractionIntent.select);
    widget.onChanged!(widget.options[next]);
  }

  void _cancel() {
    _startIndex = null;
    _distance = 0;
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.translucent,
    gestures: <Type, GestureRecognizerFactory>{
      if (widget.onChanged != null &&
          widget.options.length > 1 &&
          widget.options.contains(widget.value))
        _ScopeSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<_ScopeSwipeRecognizer>(
              () => _ScopeSwipeRecognizer(shouldAccept: _shouldAccept),
              (recognizer) {
                recognizer
                  ..shouldAccept = _shouldAccept
                  ..onPointerCancel = _cancel
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = _start
                  ..onUpdate = _update
                  ..onEnd = _end
                  ..onCancel = _cancel;
              },
            ),
    },
    child: widget.child,
  );
}

class _ScopeSwipeRecognizer extends HorizontalDragGestureRecognizer {
  _ScopeSwipeRecognizer({required this.shouldAccept})
    : super(
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      ) {
    // The switcher checks the full drag distance; the velocity tracker's
    // shorter sampling window must not discard an otherwise valid fling.
    minFlingDistance = 0;
  }

  bool Function(PointerEvent event) shouldAccept;
  VoidCallback? onPointerCancel;

  @override
  void handleEvent(PointerEvent event) {
    // An accepted Flutter drag can report onEnd for a cancelled pointer.
    // Clear the pending category before that callback is delivered.
    if (event is PointerCancelEvent) onPointerCancel?.call();
    super.handleEvent(event);
  }

  @override
  bool isPointerAllowed(PointerEvent event) =>
      shouldAccept(event) && super.isPointerAllowed(event);
}
