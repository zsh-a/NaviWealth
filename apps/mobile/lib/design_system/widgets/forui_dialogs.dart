import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Show a forui-styled confirm dialog.
///
/// Returns `true` when the user taps the confirm action, `false` for
/// cancel, `null` if the barrier was dismissed.
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required Widget title,
  Widget? body,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) {
  return showFDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx, style, animation) => FDialog(
      title: title,
      body: body,
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FButton(
          variant: destructive
              ? FButtonVariant.destructive
              : FButtonVariant.primary,
          onPress: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Show a forui-styled dialog that hosts arbitrary [child] content with
/// a single OK action. Returns `true` when OK is pressed, `null` on
/// barrier dismiss.
Future<bool?> showInfoDialog(
  BuildContext context, {
  required Widget title,
  Widget? body,
  required String okLabel,
}) {
  return showFDialog<bool>(
    context: context,
    builder: (ctx, style, animation) => FDialog(
      title: title,
      body: body,
      actions: [
        FButton(
          variant: FButtonVariant.primary,
          onPress: () => Navigator.of(ctx).pop(true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
}
