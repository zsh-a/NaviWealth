import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/providers.dart';
import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import '../data/providers.dart';
import '../domain/health_metric_kind.dart';

Future<bool?> showBodyMeasurementEntrySheet({
  required BuildContext context,
  required HealthMetricKind initialKind,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) =>
        BodyMeasurementEntrySheet(initialKind: initialKind, dirty: dirty),
  ).whenComplete(dirty.dispose);
}

class BodyMeasurementEntrySheet extends ConsumerStatefulWidget {
  const BodyMeasurementEntrySheet({
    super.key,
    required this.initialKind,
    required this.dirty,
  });

  final HealthMetricKind initialKind;
  final FormDirtyController dirty;

  @override
  ConsumerState<BodyMeasurementEntrySheet> createState() =>
      _BodyMeasurementEntrySheetState();
}

class _BodyMeasurementEntrySheetState
    extends ConsumerState<BodyMeasurementEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _valueCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  late HealthMetricKind _kind;
  late DateTime _capturedAt;
  bool _saving = false;
  String? _valueError;

  static final DateTime _firstCapturedAt = DateTime.utc(1970);

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _capturedAt = _dayAnchor(DateTime.now());
    widget.dirty.bindTextControllers([_valueCtrl, _noteCtrl]);
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = context.formatters(ref);
    final now = DateTime.now();
    final today = _calendarDay(now);
    return AppSheet(
      title: l10n.healthBodyMeasurementTitle,
      subtitle: l10n.healthBodyMeasurementSubtitle,
      footer: AppSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        onSubmit: _submit,
        busy: _saving,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedRow<HealthMetricKind>(
              options: const [
                HealthMetricKind.weight,
                HealthMetricKind.bodyFat,
              ],
              value: _kind,
              labelOf: (kind) => _labelOf(l10n, kind),
              onChanged: _saving
                  ? (_) {}
                  : (kind) {
                      setState(() {
                        _kind = kind;
                        _valueError = null;
                      });
                      widget.dirty.markDirty();
                    },
            ),
            const SizedBox(height: AppSpacing.s12),
            AmountField(
              label: _labelOf(l10n, _kind),
              controller: _valueCtrl,
              helperText: _kind == HealthMetricKind.weight
                  ? l10n.healthBodyMeasurementWeightHelper
                  : l10n.healthBodyMeasurementBodyFatHelper,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_valueError == null) return;
                setState(() => _valueError = null);
              },
            ),
            if (_valueError != null) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(
                _valueError!,
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.destructive,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s12),
            FDateField.calendar(
              label: Text(l10n.commonDate),
              control: FDateFieldControl.lifted(
                date: _calendarDay(_capturedAt),
                onChange: _saving
                    ? (_) {}
                    : (date) {
                        if (date == null) return;
                        setState(() => _capturedAt = _dayAnchor(date));
                        widget.dirty.markDirty();
                      },
                validator: (date) =>
                    date == null ? l10n.formDateFieldRequired : null,
              ),
              enabled: !_saving,
              clearable: false,
              start: _firstCapturedAt,
              end: today.add(const Duration(days: 1)),
              today: today,
              format: (context, value, format) => formatter.date(value),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _noteCtrl),
              label: Text(l10n.commonNote),
              maxLines: 3,
              minLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final decimal = Decimal.tryParse(_valueCtrl.text.trim());
    if (decimal == null) return;
    final value = double.parse(decimal.toString());
    if (_kind == HealthMetricKind.bodyFat && value > 100) {
      setState(
        () => _valueError = AppLocalizations.of(context).healthBodyFatMaxError,
      );
      Haptics.error();
      return;
    }

    setState(() => _saving = true);
    try {
      final service = await ref.read(healthMetricWriteServiceProvider.future);
      await service.recordBodyMeasurement(
        kind: _kind,
        value: value,
        capturedAt: _capturedAt,
        source: 'manual',
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      widget.dirty.markPristine();
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).healthBodyMeasurementSaveFailed('$e'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _labelOf(AppLocalizations l10n, HealthMetricKind kind) =>
      switch (kind) {
        HealthMetricKind.weight => l10n.healthMetricWeight,
        HealthMetricKind.bodyFat => l10n.healthMetricBodyFat,
        _ => kind.wire,
      };

  static DateTime _dayAnchor(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day, 12);

  static DateTime _calendarDay(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day);
}
