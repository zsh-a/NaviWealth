import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';

/// Tap-to-pick date input, rendered as a read-only [TextFormField] so it
/// inherits Material's outline + focus styling and lines up visually with
/// the other shared form widgets.
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
    // Defer the actual format until build, where we can grab the locale-aware
    // formatter; on first init we just stash the ISO date.
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
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    if (_value != null) {
      _controller.text = formatter.date(_value!);
    }
    return TextFormField(
      controller: _controller,
      readOnly: true,
      onTap: () => _pick(context),
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        suffixIcon: _value == null
            ? const Icon(Icons.calendar_today_outlined)
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: '清除',
                onPressed: widget.required
                    ? null
                    : () {
                        setState(() => _value = null);
                        _controller.clear();
                        widget.onChanged?.call(null);
                      },
              ),
        border: const OutlineInputBorder(),
      ),
      validator: (_) {
        if (widget.required && _value == null) return '请选择日期';
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
