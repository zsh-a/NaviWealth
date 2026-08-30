import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import 'app_interaction.dart';

/// App-standard button for async actions.
///
/// Keeps the label visible while busy so button width and semantics stay
/// stable, and uses the same compact spinner everywhere forms submit.
///
/// Two busy-display modes:
/// - **Inline** (default): spinner is prepended to the label as a [Row].
/// - **Prefix** ([busyPrefix] provided): the prefix slot swaps from [prefix]
///   to [busyPrefix] and the label stays plain.  Useful for small buttons
///   where the inline row would widen the button.
class AppBusyButton extends StatelessWidget {
  const AppBusyButton({
    super.key,
    required this.label,
    required this.onPress,
    this.buttonKey,
    this.busy = false,
    this.variant = FButtonVariant.primary,
    this.size,
    this.prefix,
    this.busyPrefix,
    this.busyLabel,
    this.hapticIntent = AppInteractionIntent.commit,
  });

  final Key? buttonKey;
  final String label;
  final VoidCallback? onPress;
  final bool busy;
  final FButtonVariant variant;

  /// Optional size variant.  Defaults to null (Forui's default sizing).
  final FButtonSizeVariant? size;

  /// Prefix widget shown before the label when not busy (e.g. an icon).
  final Widget? prefix;

  /// Prefix widget shown before the label when busy.
  ///
  /// When null the default inline spinner + label [Row] is used instead.
  /// Set this to a small spinner to keep the button width stable in
  /// compact layouts.
  final Widget? busyPrefix;

  /// Label shown when busy.  Falls back to [label] when null.
  final String? busyLabel;

  /// Haptic fired when the button is pressed.  Defaults to
  /// [AppInteractionIntent.commit] because this is the app's async-action
  /// button; set to null to opt out (e.g. the action itself signals).
  final AppInteractionIntent? hapticIntent;

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = busy ? (busyLabel ?? label) : label;

    final Widget child;
    if (busy && busyPrefix == null) {
      // Inline mode: spinner + label in a Row.
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: AppIconSizes.h18,
            height: AppIconSizes.h18,
            child: FCircularProgress(size: FCircularProgressSizeVariant.sm),
          ),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(effectiveLabel, maxLines: 1),
            ),
          ),
        ],
      );
    } else {
      child = Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(effectiveLabel, maxLines: 1),
        ),
      );
    }

    return FButton(
      key: buttonKey,
      variant: variant,
      size: size ?? FButtonSizeVariant.md,
      prefix: busy ? busyPrefix : prefix,
      onPress: busy
          ? null
          : switch (hapticIntent) {
              final intent? => AppInteraction.wrap(onPress, intent: intent),
              null => onPress,
            },
      child: child,
    );
  }
}
