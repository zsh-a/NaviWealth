import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';

class ExecutionSheetFooter extends StatelessWidget {
  const ExecutionSheetFooter({
    super.key,
    required this.submitLabel,
    required this.cancelLabel,
    required this.onSubmit,
    this.onCancel,
    this.enabled = true,
    this.busy = false,
    this.destructive = false,
  });

  final String submitLabel;
  final String cancelLabel;
  final VoidCallback onSubmit;
  final VoidCallback? onCancel;
  final bool enabled;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cancelButton = FButton(
      variant: FButtonVariant.outline,
      onPress: busy
          ? null
          : (onCancel ?? () => Navigator.of(context).maybePop(false)),
      child: Text(cancelLabel),
    );
    final submitButton = AppBusyButton(
      label: submitLabel,
      busyLabel: submitLabel,
      busy: busy,
      variant: destructive
          ? FButtonVariant.destructive
          : FButtonVariant.primary,
      onPress: enabled && !busy ? onSubmit : null,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final stackActions = constraints.maxWidth < 360 || textScale > 1.3;
        if (stackActions) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cancelButton,
              const SizedBox(height: AppSpacing.s8),
              submitButton,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: cancelButton),
            const SizedBox(width: AppSpacing.s12),
            Expanded(child: submitButton),
          ],
        );
      },
    );
  }
}
