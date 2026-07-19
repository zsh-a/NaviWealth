import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Label widget that appends a coloured asterisk when [required] is true.
///
/// Use as the `label` argument of [FTextFormField], [FSelect],
/// [FDateField], and similar forui form widgets to visually indicate
/// that a field must be filled before submission.
///
/// ```dart
/// FTextFormField(
///   label: RequiredLabel('Account name'),
///   // ...
/// )
/// ```
class RequiredLabel extends StatelessWidget {
  const RequiredLabel(this.text, {super.key, this.required = true, this.style});

  /// The label text.
  final String text;

  /// Whether to show the asterisk. Defaults to `true`.
  final bool required;

  /// Optional text style for the label. When `null`, the default [Text]
  /// style from the ambient [DefaultTextStyle] is used.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (!required) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        text: text,
        children: [
          TextSpan(
            text: ' *',
            style: TextStyle(color: context.theme.colors.destructive),
          ),
        ],
      ),
      style: style,
    );
  }
}
