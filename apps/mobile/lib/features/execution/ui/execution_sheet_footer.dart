import 'package:flutter/widgets.dart';

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
    return AppSheetFooter(
      submitLabel: submitLabel,
      cancelLabel: cancelLabel,
      onSubmit: onSubmit,
      onCancel: onCancel ?? () => Navigator.of(context).maybePop(false),
      enabled: enabled,
      busy: busy,
      destructive: destructive,
    );
  }
}
