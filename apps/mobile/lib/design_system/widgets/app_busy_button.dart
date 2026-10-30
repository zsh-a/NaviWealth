import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import 'app_actions.dart';
import 'app_interaction.dart';

/// App-standard button for async actions.
///
/// Keeps the label visible while busy so button width and semantics stay
/// stable, and uses the same compact spinner everywhere forms submit.
///
/// Reserves progress and label space in both states, including content-width
/// actions. Loading never shifts the label or changes the button's width.
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
    this.mainAxisSize = MainAxisSize.max,
    this.hapticIntent = AppInteractionIntent.commit,
  });

  final Key? buttonKey;
  final String label;
  final VoidCallback? onPress;
  final bool busy;
  final FButtonVariant variant;

  /// Defaults to the same large action size as [AppActionButton].
  final FButtonSizeVariant? size;

  /// Prefix widget shown before the label when not busy (e.g. an icon).
  final Widget? prefix;

  /// Prefix widget shown before the label when busy.
  ///
  /// When null the shared compact spinner occupies the reserved prefix slot.
  final Widget? busyPrefix;

  /// Label shown when busy.  Falls back to [label] when null.
  final String? busyLabel;
  final MainAxisSize mainAxisSize;

  /// Haptic fired when the button is pressed.  Defaults to
  /// [AppInteractionIntent.commit] because this is the app's async-action
  /// button; set to null to opt out (e.g. the action itself signals).
  final AppInteractionIntent? hapticIntent;

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = busy ? (busyLabel ?? label) : label;

    final progress =
        busyPrefix ??
        const FCircularProgress(size: FCircularProgressSizeVariant.sm);
    return AppActionButton(
      buttonKey: buttonKey,
      variant: variant,
      mainAxisSize: mainAxisSize,
      size: size ?? FButtonSizeVariant.lg,
      busy: busy,
      semanticsLabel: effectiveLabel,
      onPress: onPress,
      hapticIntent: hapticIntent,
      child: Flexible(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: AppIconSizes.h18,
              child: Center(child: busy ? progress : prefix),
            ),
            const SizedBox(width: AppSpacing.s8),
            Flexible(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Both labels participate in layout so longer localized
                  // busy copy cannot resize the control during a request.
                  _reserveLabel(label),
                  if (busyLabel != null) _reserveLabel(busyLabel!),
                  Text(effectiveLabel, textAlign: TextAlign.center),
                ],
              ),
            ),
            if (prefix == null) ...[
              const SizedBox(width: AppSpacing.s8),
              const SizedBox(width: AppIconSizes.h18),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _reserveLabel(String label) => Visibility.maintain(
  visible: false,
  child: Builder(
    builder: (context) => RichText(
      textAlign: TextAlign.center,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(text: label, style: DefaultTextStyle.of(context).style),
    ),
  ),
);
