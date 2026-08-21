import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_interaction.dart';

/// Visual and interaction role for an [AppSwipeAction].
enum AppSwipeActionTone { neutral, primary, danger }

/// One command revealed behind an [AppSwipeActions] row.
class AppSwipeAction {
  const AppSwipeAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tone = AppSwipeActionTone.neutral,
  });

  final String id;
  final IconData icon;
  final String label;
  final FutureOr<void> Function() onPressed;
  final AppSwipeActionTone tone;
}

/// Coordinates swipe rows so only one row in a list remains open.
class AppSwipeActionGroup extends StatefulWidget {
  const AppSwipeActionGroup({super.key, required this.child});

  final Widget child;

  @override
  State<AppSwipeActionGroup> createState() => _AppSwipeActionGroupState();
}

class _AppSwipeActionGroupState extends State<AppSwipeActionGroup> {
  Object? _owner;
  VoidCallback? _closeCurrent;

  void requestOpen(Object owner, VoidCallback close) {
    if (!identical(_owner, owner)) _closeCurrent?.call();
    _owner = owner;
    _closeCurrent = close;
  }

  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _closeCurrent = null;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.dragDetails != null) _closeCurrent?.call();
        return false;
      },
      child: _AppSwipeActionGroupScope(state: this, child: widget.child),
    );
  }
}

class _AppSwipeActionGroupScope extends InheritedWidget {
  const _AppSwipeActionGroupScope({required this.state, required super.child});

  final _AppSwipeActionGroupState state;

  static _AppSwipeActionGroupState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_AppSwipeActionGroupScope>()
      ?.state;

  @override
  bool updateShouldNotify(_AppSwipeActionGroupScope oldWidget) => false;
}

/// A row that can stop open to expose tappable actions on either side.
///
/// [leadingActions] are revealed by a start-to-end drag (rightward in LTR),
/// while [trailingActions] are revealed by an end-to-start drag. Unlike
/// [Dismissible], releasing the drag never executes an action: the user must
/// explicitly tap a revealed command. This makes the component suitable for
/// edit, AI, lifecycle, and other non-trivial operations.
class AppSwipeActions extends StatefulWidget {
  const AppSwipeActions({
    super.key,
    required this.child,
    this.leadingActions = const <AppSwipeAction>[],
    this.trailingActions = const <AppSwipeAction>[],
    this.actionExtent = 72,
    this.borderRadius = AppRadius.md,
    this.systemBackGestureInset = 24,
  }) : assert(
         leadingActions.length <= 3 && trailingActions.length <= 3,
         'Keep swipe panes short; move lower-frequency commands to a menu.',
       );

  final Widget child;
  final List<AppSwipeAction> leadingActions;
  final List<AppSwipeAction> trailingActions;
  final double actionExtent;
  final double borderRadius;
  final double systemBackGestureInset;

  @override
  State<AppSwipeActions> createState() => _AppSwipeActionsState();
}

class _AppSwipeActionsState extends State<AppSwipeActions>
    with SingleTickerProviderStateMixin {
  static const double _openThreshold = 0.28;
  static const double _flingVelocity = 650;

  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  _AppSwipeActionGroupState? _group;
  double _dragStartOffset = 0;
  bool _busy = false;

  double get _leadingExtent =>
      widget.leadingActions.length * _resolvedActionExtent;
  double get _trailingExtent =>
      widget.trailingActions.length * _resolvedActionExtent;
  double get _resolvedActionExtent {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final extra = ((scale - 1).clamp(0, 1)) * 16;
    return widget.actionExtent + extra;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _group = _AppSwipeActionGroupScope.maybeOf(context);
  }

  @override
  void didUpdateWidget(covariant AppSwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clamped = _offset.value.clamp(-_trailingExtent, _leadingExtent);
    if (clamped != _offset.value) _offset.value = clamped;
  }

  @override
  void dispose() {
    _group?.release(this);
    _offset.dispose();
    super.dispose();
  }

  double _logicalDelta(BuildContext context, double physicalDelta) {
    return Directionality.of(context) == TextDirection.ltr
        ? physicalDelta
        : -physicalDelta;
  }

  void _handleDragStart(DragStartDetails details) {
    _offset.stop();
    _dragStartOffset = _offset.value;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = _logicalDelta(context, details.primaryDelta ?? 0);
    _offset.value = (_offset.value + delta).clamp(
      -_trailingExtent,
      _leadingExtent,
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = _logicalDelta(
      context,
      details.primaryVelocity ?? details.velocity.pixelsPerSecond.dx,
    );
    final value = _offset.value;
    double target = 0;
    if (velocity.abs() >= _flingVelocity) {
      if (velocity > 0 && _leadingExtent > 0) target = _leadingExtent;
      if (velocity < 0 && _trailingExtent > 0) target = -_trailingExtent;
    } else if (value > _leadingExtent * _openThreshold && _leadingExtent > 0) {
      target = _leadingExtent;
    } else if (value < -_trailingExtent * _openThreshold &&
        _trailingExtent > 0) {
      target = -_trailingExtent;
    }
    unawaited(_animateTo(target));
  }

  Future<void> _animateTo(double target) async {
    if (target != 0) {
      _group?.requestOpen(this, _closeFromGroup);
      if (_dragStartOffset == 0) {
        AppInteraction.signal(AppInteractionIntent.reveal);
      }
    } else {
      _group?.release(this);
    }
    await _offset.animateTo(
      target,
      duration: AppMotionPolicy.duration(context, Motion.componentChange),
      curve: Motion.emphasizedDecelerate,
    );
  }

  void _closeFromGroup() {
    if (!mounted) return;
    unawaited(_animateTo(0));
  }

  Future<void> _activate(AppSwipeAction action) async {
    if (_busy) return;
    _busy = true;
    AppInteraction.signal(switch (action.tone) {
      AppSwipeActionTone.danger => AppInteractionIntent.destroy,
      AppSwipeActionTone.primary => AppInteractionIntent.commit,
      AppSwipeActionTone.neutral => AppInteractionIntent.select,
    });
    try {
      await _animateTo(0);
      await action.onPressed();
    } finally {
      _busy = false;
    }
  }

  bool _shouldAcceptClosedDrag(PointerEvent event) {
    if (Theme.of(context).platform != TargetPlatform.iOS) return true;
    return event.localPosition.dx > widget.systemBackGestureInset;
  }

  @override
  Widget build(BuildContext context) {
    final customActions = <CustomSemanticsAction, VoidCallback>{
      for (final action in <AppSwipeAction>[
        ...widget.leadingActions,
        ...widget.trailingActions,
      ])
        CustomSemanticsAction(label: action.label): () {
          unawaited(_activate(action));
        },
    };
    return Semantics(
      customSemanticsActions: customActions,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: AnimatedBuilder(
          animation: _offset,
          builder: (context, child) {
            final logicalOffset = _offset.value;
            final physicalOffset =
                Directionality.of(context) == TextDirection.ltr
                ? logicalOffset
                : -logicalOffset;
            return Stack(
              children: [
                if (widget.leadingActions.isNotEmpty)
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: _leadingExtent,
                    child: _ActionPane(
                      actions: widget.leadingActions,
                      actionExtent: _resolvedActionExtent,
                      onPressed: _activate,
                    ),
                  ),
                if (widget.trailingActions.isNotEmpty)
                  PositionedDirectional(
                    end: 0,
                    top: 0,
                    bottom: 0,
                    width: _trailingExtent,
                    child: _ActionPane(
                      actions: widget.trailingActions,
                      actionExtent: _resolvedActionExtent,
                      onPressed: _activate,
                    ),
                  ),
                Transform.translate(
                  offset: Offset(physicalOffset, 0),
                  child: Stack(
                    children: [
                      child!,
                      if (logicalOffset.abs() > 0.5)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _closeFromGroup,
                            onHorizontalDragStart: _handleDragStart,
                            onHorizontalDragUpdate: _handleDragUpdate,
                            onHorizontalDragEnd: _handleDragEnd,
                            onHorizontalDragCancel: _closeFromGroup,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
          child: RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: <Type, GestureRecognizerFactory>{
              _EdgeAwareHorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _EdgeAwareHorizontalDragGestureRecognizer
                  >(
                    () => _EdgeAwareHorizontalDragGestureRecognizer(
                      shouldAccept: _shouldAcceptClosedDrag,
                    ),
                    (recognizer) {
                      recognizer
                        ..shouldAccept = _shouldAcceptClosedDrag
                        ..dragStartBehavior = DragStartBehavior.down
                        ..onStart = _handleDragStart
                        ..onUpdate = _handleDragUpdate
                        ..onEnd = _handleDragEnd
                        ..onCancel = _closeFromGroup;
                    },
                  ),
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _EdgeAwareHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  _EdgeAwareHorizontalDragGestureRecognizer({required this.shouldAccept});

  bool Function(PointerEvent event) shouldAccept;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      shouldAccept(event) && super.isPointerAllowed(event);
}

class _ActionPane extends StatelessWidget {
  const _ActionPane({
    required this.actions,
    required this.actionExtent,
    required this.onPressed,
  });

  final List<AppSwipeAction> actions;
  final double actionExtent;
  final Future<void> Function(AppSwipeAction action) onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in actions)
          SizedBox(
            width: actionExtent,
            child: _ActionButton(action: action, onPressed: onPressed),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, required this.onPressed});

  final AppSwipeAction action;
  final Future<void> Function(AppSwipeAction action) onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final role = switch (action.tone) {
      AppSwipeActionTone.neutral => (
        background: colors.muted,
        foreground: colors.foreground,
      ),
      AppSwipeActionTone.primary => (
        background: context.appTheme.accent.container,
        foreground: context.appTheme.accent.onContainer,
      ),
      AppSwipeActionTone.danger => (
        background: context.appTheme.status.danger.container,
        foreground: context.appTheme.status.danger.onContainer,
      ),
    };
    return Semantics(
      button: true,
      label: action.label,
      child: FTappable(
        key: ValueKey<String>('app-swipe-action.${action.id}'),
        onPress: () => unawaited(onPressed(action)),
        child: ColoredBox(
          color: role.background,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    action.icon,
                    size: AppIconSizes.h18,
                    color: role.foreground,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    action.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.linear(
                      MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.3),
                    ),
                    style: context.labelStyle.copyWith(color: role.foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
