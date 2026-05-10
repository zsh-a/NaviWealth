import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../l10n/gen/app_localizations.dart';

/// Decimal-precision amount entry built on [FTextFormField].
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
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
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
    _effectiveController.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null && oldWidget.controller != null) {
      oldWidget.controller!.removeListener(_onTextChanged);
      _internalController = TextEditingController(
        text: oldWidget.controller!.text,
      );
      _internalController!.addListener(_onTextChanged);
    } else if (widget.controller != null && oldWidget.controller == null) {
      _internalController?.removeListener(_onTextChanged);
      _internalController?.dispose();
      _internalController = null;
      widget.controller!.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    if (widget.onChanged == null) return;
    widget.onChanged!(Decimal.tryParse(_effectiveController.text.trim()));
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_onTextChanged);
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pattern = widget.allowNegative
        ? RegExp(r'^-?\d*\.?\d*$')
        : RegExp(r'^\d*\.?\d*$');
    return FTextFormField(
      control: FTextFieldControl.managed(controller: _effectiveController),
      focusNode: widget.focusNode,
      textInputAction: widget.textInputAction ?? TextInputAction.next,
      onSubmit: widget.onFieldSubmitted,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(pattern)],
      label: Text(widget.label),
      hint: widget.currencyCode == null ? null : '${widget.currencyCode} ',
      description: widget.helperText == null ? null : Text(widget.helperText!),
      validator: (value) {
        final trimmed = value?.trim() ?? '';
        if (trimmed.isEmpty) {
          return widget.required ? l10n.formAmountFieldRequired : null;
        }
        final parsed = Decimal.tryParse(trimmed);
        if (parsed == null) return l10n.formAmountFieldInvalid;
        if (!widget.allowNegative && parsed < Decimal.zero) {
          return l10n.formAmountFieldNegativeNotAllowed;
        }
        return null;
      },
    );
  }
}

/// Resolve the entered text from an [AmountField] to a [Decimal].
Decimal? readAmount(TextEditingController controller) {
  return Decimal.tryParse(controller.text.trim());
}
