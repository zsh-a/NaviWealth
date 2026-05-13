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
  Locale? _locale;
  bool _syncQueued = false;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _syncController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_locale != locale) {
      _locale = locale;
      _syncController();
    }
  }

  @override
  void didUpdateWidget(DateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _value = widget.initialValue;
      _queueControllerSync();
    }
  }

  String _format(DateTime? value) {
    if (value == null) return '';
    final locale = _locale;
    if (locale == null) {
      return value.toIso8601String().split('T').first;
    }
    return AppFormatters(locale: locale).date(value);
  }

  void _syncController() {
    final text = _format(_value);
    if (_controller.text != text) {
      _controller.text = text;
    }
  }

  void _queueControllerSync() {
    if (_syncQueued) return;
    _syncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncQueued = false;
      if (!mounted) return;
      _syncController();
    });
  }

  void _setValue(DateTime? value) {
    setState(() {
      _value = value;
      _syncController();
    });
    widget.onChanged?.call(value);
  }

  DateTime _clampInitialDate(DateTime date, DateTime first, DateTime last) {
    if (date.isBefore(first)) return first;
    if (date.isAfter(last)) return last;
    return date;
  }

  Future<void> _pick(BuildContext context) async {
    final today = DateTime.now();
    final firstDate =
        widget.firstDate ?? DateTime(today.year - 30, today.month, today.day);
    final lastDate =
        widget.lastDate ?? DateTime(today.year + 30, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _clampInitialDate(_value ?? today, firstDate, lastDate),
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null) return;
    _setValue(picked);
  }

  void _clear() {
    if (widget.required) return;
    _setValue(null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                onPress: widget.required ? null : _clear,
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
