import 'package:flutter/material.dart' show Icons, showDatePicker;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Tap-to-pick date input rendered on top of [FTextFormField].
class DateField extends StatefulWidget {
  const DateField({
    super.key,
    required this.label,
    this.initialValue,
    this.onChanged,
    this.firstDate,
    this.lastDate,
    this.required = false,
    this.helperText,
  });

  final String label;
  final DateTime? initialValue;
  final ValueChanged<DateTime?>? onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool required;
  final String? helperText;

  @override
  State<DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<DateField> {
  late DateTime? _value;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _syncController();
  }

  @override
  void didUpdateWidget(DateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _value = widget.initialValue;
      _syncController();
    }
  }

  void _syncController() {
    if (_value == null) {
      _controller.text = '';
      return;
    }
    _controller.text = _value!.toIso8601String().split('T').first;
  }

  Future<void> _pick(BuildContext context) async {
    final today = DateTime.now();
    final firstDate =
        widget.firstDate ?? DateTime(today.year - 30, today.month, today.day);
    final lastDate =
        widget.lastDate ?? DateTime(today.year + 30, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _value ?? today,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null) return;
    setState(() => _value = picked);
    widget.onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    if (_value != null) {
      _controller.text = formatter.date(_value!);
    }
    return FTextFormField(
      control: FTextFieldControl.managed(controller: _controller),
      readOnly: true,
      onTap: () => _pick(context),
      label: Text(widget.label),
      description: widget.helperText == null ? null : Text(widget.helperText!),
      suffixBuilder: (ctx, style, variants) => _value == null
          ? Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: ctx.theme.colors.mutedForeground,
              ),
            )
          : Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: widget.required
                    ? null
                    : () {
                        setState(() => _value = null);
                        _controller.clear();
                        widget.onChanged?.call(null);
                      },
                child: Icon(
                  Icons.clear,
                  size: 18,
                  semanticLabel: l10n.formDateFieldClearTooltip,
                ),
              ),
            ),
      validator: (_) {
        if (widget.required && _value == null) {
          return l10n.formDateFieldRequired;
        }
        return null;
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
