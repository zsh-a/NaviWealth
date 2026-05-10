import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../l10n/gen/app_localizations.dart';

/// Multiline note / 备注 entry. Uses [FTextFormField] so saved input
/// survives scroll/focus state in the same way as the rest of the form.
class NoteField extends StatelessWidget {
  const NoteField({
    super.key,
    this.controller,
    this.label,
    this.maxLines = 3,
    this.maxLength = 500,
    this.helperText,
    this.focusNode,
  });

  final TextEditingController? controller;
  final String? label;
  final int maxLines;
  final int maxLength;
  final String? helperText;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final resolvedLabel =
        label ?? AppLocalizations.of(context).formNoteFieldLabelDefault;
    return FTextFormField(
      control: FTextFieldControl.managed(controller: controller),
      focusNode: focusNode,
      minLines: 2,
      maxLines: maxLines,
      maxLength: maxLength,
      textInputAction: TextInputAction.newline,
      label: Text(resolvedLabel),
      description: helperText == null ? null : Text(helperText!),
    );
  }
}
