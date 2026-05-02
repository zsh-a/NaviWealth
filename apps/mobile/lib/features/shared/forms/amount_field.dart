import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/design_system.dart';

/// Decimal-precision amount entry.
///
/// We expose a plain [TextFormField] under the hood — Material's currency
/// fields don't preserve trailing zeros and silently coerce to `double`,
/// which is exactly the bug we're trying to avoid by using [Decimal] in
/// the model.
///
/// `validator` returns `null` on success, or the localised error string;
/// callers compose it with [FormState.validate] in the usual way.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.label,
    this.initialValue,
    this.controller,
    this.currencyCode,
    this.allowNegative = false,
    this.required = true,
    this.helperText,
    this.onChanged,
    this.focusNode,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final String label;
  final Decimal? initialValue;
  final TextEditingController? controller;
  final String? currencyCode;
  final bool allowNegative;
  final bool required;
  final String? helperText;
  final void Function(Decimal? value)? onChanged;

  /// Optional focus node so callers can chain fields with
  /// `TextInputAction.next` and the soft-keyboard "next" arrow jumps to
  /// the right input. When omitted Flutter creates one internally and
  /// focus traversal falls back to widget order.
  final FocusNode? focusNode;

  /// Defaults to [TextInputAction.next] when null so callers wiring a
  /// focus chain just get the right keyboard affordance for free.
  final TextInputAction? textInputAction;

  /// Invoked when the user hits the keyboard action button. Pair with
  /// [textInputAction] = `done` on the last field so a single keypress
  /// submits the form.
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  TextEditingController? _internalController;

  TextEditingController get _effectiveController =>
      widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = TextEditingController(
        text: widget.initialValue?.toString() ?? '',
      );
    }
  }

  @override
  void didUpdateWidget(AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null && oldWidget.controller != null) {
      // Caller dropped their controller; take over with an internal one
      // seeded from the last known text so we don't lose the user's input.
      _internalController = TextEditingController(
        text: oldWidget.controller!.text,
      );
    } else if (widget.controller != null && oldWidget.controller == null) {
      _internalController?.dispose();
      _internalController = null;
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pattern = widget.allowNegative
        ? RegExp(r'^-?\d*\.?\d*$')
        : RegExp(r'^\d*\.?\d*$');
    return TextFormField(
      controller: _effectiveController,
      focusNode: widget.focusNode,
      textInputAction: widget.textInputAction ?? TextInputAction.next,
      onFieldSubmitted: widget.onFieldSubmitted,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(pattern)],
      style: TypographyTokens.numericBody.copyWith(
        fontFeatures: TypographyTokens.tabularFigures,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        prefixText: widget.currencyCode == null ? null : '${widget.currencyCode} ',
        helperText: widget.helperText,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final trimmed = value?.trim() ?? '';
        if (trimmed.isEmpty) {
          return widget.required ? '请输入金额' : null;
        }
        final parsed = Decimal.tryParse(trimmed);
        if (parsed == null) return '金额格式不正确';
        if (!widget.allowNegative && parsed < Decimal.zero) return '金额不能为负';
        return null;
      },
      onChanged: widget.onChanged == null
          ? null
          : (raw) {
              widget.onChanged!(Decimal.tryParse(raw.trim()));
            },
    );
  }
}

/// Resolve the entered text from an [AmountField] to a [Decimal].
Decimal? readAmount(TextEditingController controller) {
  return Decimal.tryParse(controller.text.trim());
}
