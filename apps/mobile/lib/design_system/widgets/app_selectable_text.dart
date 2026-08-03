import 'package:flutter/material.dart';

/// Design-system boundary around Material's selectable text primitive.
///
/// Feature packages consume this wrapper so text selection stays available on
/// every platform without importing Material UI directly.
class AppSelectableText extends StatelessWidget {
  const AppSelectableText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.textAlign,
  }) : textSpan = null;

  const AppSelectableText.rich(
    this.textSpan, {
    super.key,
    this.maxLines,
    this.textAlign,
  }) : data = null,
       style = null;

  final String? data;
  final TextSpan? textSpan;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final span = textSpan;
    if (span != null) {
      return SelectableText.rich(
        span,
        maxLines: maxLines,
        textAlign: textAlign ?? TextAlign.start,
      );
    }
    return SelectableText(
      data ?? '',
      style: style,
      maxLines: maxLines,
      textAlign: textAlign,
    );
  }
}
