import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';

/// App-standard button for async actions.
///
/// Keeps the label visible while busy so button width and semantics stay
/// stable, and uses the same compact spinner everywhere forms submit.
class AppBusyButton extends StatelessWidget {
  const AppBusyButton({
    super.key,
    required this.label,
    required this.onPress,
    this.buttonKey,
    this.busy = false,
    this.variant = FButtonVariant.primary,
  });

  final Key? buttonKey;
  final String label;
  final VoidCallback? onPress;
  final bool busy;
  final FButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    return FButton(
      key: buttonKey,
      variant: variant,
      onPress: busy ? null : onPress,
      child: busy
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: AppIconSizes.h18,
                  height: AppIconSizes.h18,
                  child: FCircularProgress(
                    size: FCircularProgressSizeVariant.sm,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(label),
              ],
            )
          : Text(label),
    );
  }
}
