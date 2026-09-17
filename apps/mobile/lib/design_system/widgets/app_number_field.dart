import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import '../tokens/typography_tokens.dart';

/// Shared numeric presentation; range, precision and conversion belong to callers.
class AppNumberField extends StatelessWidget {
  const AppNumberField({
    super.key,
    required this.control,
    this.label,
    this.unit,
    this.description,
    this.hint,
    this.validator,
    this.forceErrorText,
    this.enabled = true,
    this.focusNode,
    this.textInputAction = TextInputAction.next,
    this.onSubmit,
    this.keyboardType = const TextInputType.numberWithOptions(decimal: true),
    this.inputFormatters,
  });

  final FTextFieldControl control;
  final Widget? label;
  final String? unit;
  final Widget? description;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final String? forceErrorText;
  final bool enabled;
  final FocusNode? focusNode;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmit;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTextFormField(
      control: control,
      label: label,
      description: description,
      hint: hint,
      enabled: enabled,
      focusNode: focusNode,
      textAlign: TextAlign.end,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmit: onSubmit,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: inputFormatters,
      validator: validator,
      forceErrorText: forceErrorText,
      style: FTextFieldStyleDelta.delta(
        color: FVariants.from(
          colors.secondary.withValues(alpha: 0.35),
          variants: const {},
        ),
        contentTextStyle: FVariants.from(
          TypographyTokens.numericBodyStrong.copyWith(color: colors.foreground),
          variants: {
            [FTextFieldVariant.disabled]: TextStyleDelta.delta(
              color: colors.mutedForeground,
            ),
          },
        ),
      ),
      suffixBuilder: unit == null
          ? null
          : (_, style, variants) => Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.s4,
                end: AppSpacing.s12,
              ),
              child: Text(unit!, style: context.captionStyle),
            ),
    );
  }
}
