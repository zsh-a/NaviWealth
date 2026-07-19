import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

/// Keyboard activation shared by app-owned button primitives.
///
/// The trailing no-op bindings consume repeat events that would otherwise
/// bubble to [WidgetsApp]'s default Enter/Space shortcuts.
const Map<ShortcutActivator, Intent> appActionActivationShortcuts = {
  SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
      ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
      ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.enter): DoNothingIntent(),
  SingleActivator(LogicalKeyboardKey.space): DoNothingIntent(),
};

/// The current theme's large button height, used as the minimum action target.
double appActionTargetSize(BuildContext context) =>
    context.theme.buttonStyles.primary.lg.contentStyle.constraints.minHeight;

Map<Type, Action<Intent>>? _disabledActivationActions(VoidCallback? onPress) =>
    onPress == null
    ? <Type, Action<Intent>>{ActivateIntent: _DisabledActivateAction()}
    : null;

class _DisabledActivateAction extends Action<ActivateIntent> {
  @override
  void invoke(ActivateIntent intent) {}
}

/// App-owned text action with a large Forui target and reliable keyboard use.
///
/// [FButton] 0.23 declares shortcut/action fields but does not forward them
/// from `build`; this component uses a controlled private subclass until the
/// upstream implementation does so.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.onPress,
    required this.child,
    this.variant = FButtonVariant.primary,
    this.prefix,
    this.mainAxisSize = MainAxisSize.max,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
  });

  final VoidCallback? onPress;
  final FButtonVariant variant;
  final Widget? prefix;
  final Widget child;
  final MainAxisSize mainAxisSize;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    return _ManagedActionFocus(
      enabled: onPress != null,
      focusNode: focusNode,
      builder: (focusNode) => _AppActionFButton(
        onPress: onPress,
        variant: variant,
        prefix: prefix,
        mainAxisSize: mainAxisSize,
        autofocus: autofocus,
        focusNode: focusNode,
        onFocusChange: onFocusChange,
        child: child,
      ),
    );
  }
}

/// Header icon action with an explicit accessible name and large hit target.
class AppHeaderAction extends StatelessWidget {
  const AppHeaderAction({
    super.key,
    required this.semanticsLabel,
    required this.icon,
    required this.onPress,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
  }) : assert(semanticsLabel != '', 'semanticsLabel must not be empty');

  final String semanticsLabel;
  final Widget icon;
  final VoidCallback? onPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final targetSize = appActionTargetSize(context);
    return FTooltip(
      tipBuilder: (_, _) => Text(semanticsLabel),
      child: Semantics(
        container: true,
        button: true,
        enabled: onPress != null,
        label: semanticsLabel,
        onTap: onPress,
        excludeSemantics: true,
        child: _ManagedActionFocus(
          enabled: onPress != null,
          focusNode: focusNode,
          builder: (focusNode) => FHeaderAction(
            style: const FHeaderActionStyleDelta.delta(
              padding: EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
            ),
            semanticsLabel: semanticsLabel,
            icon: SizedBox.square(
              dimension: targetSize,
              child: Center(child: ExcludeSemantics(child: icon)),
            ),
            autofocus: autofocus,
            focusNode: focusNode,
            onFocusChange: onFocusChange,
            onPress: onPress,
            shortcuts: appActionActivationShortcuts,
            actions: _disabledActivationActions(onPress),
          ),
        ),
      ),
    );
  }
}

class _AppActionFButton extends FButton {
  _AppActionFButton({
    required super.onPress,
    required super.variant,
    required super.child,
    super.prefix,
    super.mainAxisSize,
    super.autofocus,
    super.focusNode,
    super.onFocusChange,
  }) : super(
         size: FButtonSizeVariant.lg,
         shortcuts: appActionActivationShortcuts,
         actions: _disabledActivationActions(onPress),
       );

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style(
      context.theme.buttonStyles
          .resolve({variant, context.platformVariant})
          .resolve({size, context.platformVariant}),
    );

    return FTappable(
      style: resolvedStyle.tappableStyle,
      focusedOutlineStyle: resolvedStyle.focusedOutlineStyle,
      autofocus: autofocus,
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      onHoverChange: onHoverChange,
      onVariantChange: onVariantChange,
      onPress: onPress,
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      onSecondaryPress: onSecondaryPress,
      onSecondaryLongPress: onSecondaryLongPress,
      selected: selected,
      semanticsLabel: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      shortcuts: shortcuts,
      actions: actions,
      builder: (_, variants, _) => DecoratedBox(
        decoration: resolvedStyle.decoration.resolve(variants),
        child: FButtonData(
          style: resolvedStyle,
          variants: variants,
          child: child,
        ),
      ),
    );
  }
}

class _ManagedActionFocus extends StatefulWidget {
  const _ManagedActionFocus({
    required this.enabled,
    required this.focusNode,
    required this.builder,
  });

  final bool enabled;
  final FocusNode? focusNode;
  final Widget Function(FocusNode focusNode) builder;

  @override
  State<_ManagedActionFocus> createState() => _ManagedActionFocusState();
}

class _ManagedActionFocusState extends State<_ManagedActionFocus> {
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'AppAction'));

  @override
  void didUpdateWidget(covariant _ManagedActionFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFocusNode = oldWidget.focusNode ?? _ownedFocusNode;
    if (oldWidget.enabled && !widget.enabled) {
      oldFocusNode?.unfocus();
    }
    if (oldWidget.focusNode != widget.focusNode &&
        oldWidget.focusNode == null) {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_focusNode);
}
