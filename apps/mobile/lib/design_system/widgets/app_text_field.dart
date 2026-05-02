import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';
import '../tokens/spacing_tokens.dart';

/// Stripe-style text field with a bottom-rule underline that transitions
/// to emerald on focus and crimson on error.
///
/// Replaces Material's outlined / filled InputDecoration with a minimal
/// single-line treatment. The label sits above the input as a caption,
/// not as a floating hint.
///
/// Usage:
/// ```dart
/// AppTextField(
///   label: 'Amount',
///   controller: ctrl,
///   keyboardType: TextInputType.number,
/// )
/// ```
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.prefix,
    this.suffix,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.validator,
    this.inputFormatters,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.decoration,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final Widget? prefix;
  final Widget? suffix;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final List<dynamic>? inputFormatters;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final InputDecoration? decoration;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_hasFocus != _focusNode.hasFocus) {
      setState(() => _hasFocus = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final hasError = widget.errorText != null;

    final borderColor = hasError
        ? ColorPalette.red500
        : _hasFocus
            ? ColorPalette.green500
            : (isDark ? ColorPalette.neutral600 : ColorPalette.neutral300);

    final border = UnderlineInputBorder(
      borderSide: BorderSide(color: borderColor, width: _hasFocus ? 1.5 : 1),
    );

    const errorBorder = UnderlineInputBorder(
      borderSide: BorderSide(color: ColorPalette.red500, width: 1.5),
    );

    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: hasError
          ? ColorPalette.red500
          : _hasFocus
              ? ColorPalette.green500
              : cs.onSurfaceVariant,
    );

    final inputDecoration = (widget.decoration ?? const InputDecoration()).copyWith(
      labelText: null, // We use our own label above
      hintText: widget.hint,
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      errorText: widget.errorText,
      errorStyle: theme.textTheme.bodySmall?.copyWith(color: ColorPalette.red500),
      prefixIcon: widget.prefix,
      suffixIcon: widget.suffix,
      enabledBorder: border,
      focusedBorder: border,
      errorBorder: errorBorder,
      focusedErrorBorder: errorBorder,
      disabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(
          color: (isDark ? ColorPalette.neutral700 : ColorPalette.neutral200),
          width: 1,
        ),
      ),
      contentPadding: const EdgeInsets.only(
        top: Spacing.s8,
        bottom: Spacing.s8,
      ),
      isDense: true,
    );

    final textField = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: widget.obscureText,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      autofillHints: widget.autofillHints,
      textCapitalization: widget.textCapitalization,
      style: widget.style ?? theme.textTheme.bodyMedium,
      decoration: inputDecoration,
    );

    if (widget.label == null) return textField;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label!, style: labelStyle),
        const SizedBox(height: Spacing.s4),
        textField,
      ],
    );
  }
}
