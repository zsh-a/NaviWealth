import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
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
    this.includeTime = false,
    this.enabled = true,
  });

  final String label;
  final DateTime? initialValue;
  final ValueChanged<DateTime?>? onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool required;
  final String? helperText;
  final bool includeTime;
  final bool enabled;

  @override
  State<DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<DateField> {
  late DateTime? _value;
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_locale != locale) {
      _locale = locale;
    }
  }

  @override
  void didUpdateWidget(DateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _value = widget.initialValue;
    }
  }

  String _format(DateTime? value) {
    if (value == null) return '';
    final locale = _locale;
    if (locale == null) {
      return value.toIso8601String().split('T').first;
    }
    final formatters = AppFormatters(locale: locale);
    return widget.includeTime
        ? formatters.dateTime(value)
        : formatters.date(value);
  }

  String _formatDate(DateTime value) {
    final locale = _locale;
    if (locale == null) {
      return value.toIso8601String().split('T').first;
    }
    return AppFormatters(locale: locale).date(value);
  }

  void _setValue(DateTime? value) {
    setState(() => _value = value);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final today = DateTime.now();
    final firstDate =
        widget.firstDate ?? DateTime(today.year - 30, today.month, today.day);
    final lastDate =
        widget.lastDate ?? DateTime(today.year + 30, today.month, today.day);
    if (widget.includeTime) {
      return _DateTimeField(
        label: widget.label,
        value: _value,
        helperText: widget.helperText,
        required: widget.required,
        enabled: widget.enabled,
        firstDate: firstDate,
        lastDate: lastDate,
        format: _format,
        formatDate: _formatDate,
        onChanged: _setValue,
      );
    }
    return FDateField.calendar(
      control: FDateFieldControl.lifted(
        date: _value == null ? null : _calendarDay(_value!),
        onChange: (date) {
          if (date == null) {
            _setValue(null);
            return;
          }
          final existing = _value;
          _setValue(
            widget.includeTime && existing != null
                ? DateTime(
                    date.year,
                    date.month,
                    date.day,
                    existing.hour,
                    existing.minute,
                    existing.second,
                    existing.millisecond,
                    existing.microsecond,
                  )
                : date,
          );
        },
        validator: (date) {
          if (widget.required && date == null) {
            return l10n.formDateFieldRequired;
          }
          return null;
        },
      ),
      label: Text(widget.label),
      description: widget.helperText == null ? null : Text(widget.helperText!),
      enabled: widget.enabled,
      start: _calendarDay(firstDate),
      end: _calendarDay(lastDate),
      today: _calendarDay(today),
      clearable: !widget.required,
      format: (context, value, format) => _format(_value ?? value),
    );
  }

  static DateTime _calendarDay(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day);
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.helperText,
    required this.required,
    required this.enabled,
    required this.firstDate,
    required this.lastDate,
    required this.format,
    required this.formatDate,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final String? helperText;
  final bool required;
  final bool enabled;
  final DateTime firstDate;
  final DateTime lastDate;
  final String Function(DateTime? value) format;
  final String Function(DateTime value) formatDate;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateValue = value == null ? null : _calendarDay(value!);
    final timeValue = value == null ? null : FTime.fromDateTime(value!);
    final description = helperText == null ? null : Text(helperText!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: FDateField.calendar(
            control: FDateFieldControl.lifted(
              date: dateValue,
              onChange: (date) {
                if (date == null) {
                  onChanged(null);
                  return;
                }
                onChanged(_combine(date, timeValue ?? FTime.now()));
              },
              validator: (date) {
                if (required && date == null) {
                  return l10n.formDateFieldRequired;
                }
                return null;
              },
            ),
            label: Text(label),
            description: description,
            enabled: enabled,
            start: _calendarDay(firstDate),
            end: _calendarDay(lastDate),
            today: _calendarDay(DateTime.now()),
            clearable: !required,
            format: (context, value, format) => formatDate(value),
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          flex: 2,
          child: FTimeField.picker(
            control: FTimeFieldControl.lifted(
              time: timeValue,
              onChange: (FTime? time) {
                if (time == null) {
                  onChanged(null);
                  return;
                }
                onChanged(
                  _combine(dateValue ?? _calendarDay(DateTime.now()), time),
                );
              },
            ),
            label: Text(l10n.formDateFieldTimeLabel),
            enabled: enabled,
            hour24: true,
            clearable: !required,
            forceErrorText: required && timeValue == null
                ? l10n.formDateFieldRequired
                : null,
          ),
        ),
      ],
    );
  }

  DateTime _combine(DateTime date, FTime time) {
    return _clamp(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  DateTime _clamp(DateTime dateTime) {
    final first = DateTime(
      firstDate.year,
      firstDate.month,
      firstDate.day,
      0,
      0,
    );
    final last = DateTime(
      lastDate.year,
      lastDate.month,
      lastDate.day,
      23,
      59,
      59,
      999,
      999,
    );
    if (dateTime.isBefore(first)) return first;
    if (dateTime.isAfter(last)) return last;
    return dateTime;
  }

  static DateTime _calendarDay(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day);
}
