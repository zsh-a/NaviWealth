import 'package:flutter/material.dart';

/// Multiline note / 备注 entry. Uses [TextFormField] so saved input survives
/// scroll/focus state in the same way as the rest of the form.
class NoteField extends StatelessWidget {
  const NoteField({
    super.key,
    this.controller,
    this.label = '备注',
    this.maxLines = 3,
    this.maxLength = 500,
    this.helperText,
    this.focusNode,
  });

  final TextEditingController? controller;
  final String label;
  final int maxLines;
  final int maxLength;
  final String? helperText;

  /// Optional focus node so callers can wire the note field into a
  /// keyboard focus chain (`textInputAction.next` jumps here from the
  /// preceding amount field). The note itself accepts newlines, so we
  /// keep [TextInputAction.newline] regardless.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      minLines: 2,
      maxLines: maxLines,
      maxLength: maxLength,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
