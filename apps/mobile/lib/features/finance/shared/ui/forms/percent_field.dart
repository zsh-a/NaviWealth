import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../../../core/forms/percent_input_formatter.dart';
import '../../../../../design_system/design_system.dart';

/// Percentage points in the editor; callers own conversion to stored ratios.
class PercentField extends StatelessWidget {
  const PercentField({
    super.key,
    required this.control,
    required this.label,
    this.validator,
    this.forceErrorText,
    this.enabled = true,
    this.compact = false,
    this.semanticLabel,
    this.description,
    this.focusNode,
    this.textInputAction = TextInputAction.next,
    this.onSubmit,
    this.allowNegative = false,
    this.inputFormatters,
    this.decimalPlaces = 2,
  });

  final FTextFieldControl control;
  final Widget label;
  final FormFieldValidator<String>? validator;
  final String? forceErrorText;
  final bool enabled;
  final bool compact;
  final String? semanticLabel;
  final Widget? description;
  final FocusNode? focusNode;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmit;
  final bool allowNegative;
  final List<TextInputFormatter>? inputFormatters;
  final int? decimalPlaces;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: AppNumberField(
      control: control,
      label: compact ? null : label,
      unit: '%',
      description: description,
      enabled: enabled,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onSubmit: onSubmit,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: allowNegative,
      ),
      inputFormatters:
          inputFormatters ??
          [
            PercentInputFormatter(
              allowNegative: allowNegative,
              decimalPlaces: decimalPlaces,
            ),
          ],
      validator: validator,
      forceErrorText: forceErrorText,
    ),
  );
}
