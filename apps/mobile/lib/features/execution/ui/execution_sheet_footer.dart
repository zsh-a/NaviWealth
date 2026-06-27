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
    return Row(
      children: [
        Expanded(
          child: FButton(
            variant: FButtonVariant.outline,
            onPress: busy
                ? null
                : (onCancel ?? () => Navigator.of(context).maybePop(false)),
            child: Text(cancelLabel),
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: AppBusyButton(
            label: submitLabel,
            busyLabel: submitLabel,
            busy: busy,
            variant: destructive
                ? FButtonVariant.destructive
                : FButtonVariant.primary,
            onPress: enabled && !busy ? onSubmit : null,
          ),
        ),
      ],
    );
  }
}
