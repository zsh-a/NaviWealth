import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
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
  );
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
    final dateFormat = DateFormat.yMMMd(
      Localizations.maybeLocaleOf(context)?.toString(),
    );
    return AppSheet(
      title: '记录身体指标',
      subtitle: '适合体重、体脂这类低频手动录入数据',
      footer: AppSheetFooter(
        submitLabel: '保存',
        cancelLabel: '取消',
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
              labelOf: _labelOf,
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
              label: _kind == HealthMetricKind.weight ? '体重' : '体脂',
              controller: _valueCtrl,
              helperText: _kind == HealthMetricKind.weight
                  ? '单位：kg'
                  : '单位：%，例如 18.5',
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
            FTappable(
              onPress: _saving ? null : _pickDate,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '日期',
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    dateFormat.format(_capturedAt),
                    style: context.theme.typography.sm,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _noteCtrl),
              label: const Text('备注'),
              maxLines: 3,
              minLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _capturedAt,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _capturedAt = _dayAnchor(picked));
    widget.dirty.markDirty();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final decimal = Decimal.tryParse(_valueCtrl.text.trim());
    if (decimal == null) return;
    final value = double.parse(decimal.toString());
    if (_kind == HealthMetricKind.bodyFat && value > 100) {
      setState(() => _valueError = '体脂不能超过 100%');
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
      Haptics.error();
      AppMessenger.show(context, ToastKind.error, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _labelOf(HealthMetricKind kind) => switch (kind) {
    HealthMetricKind.weight => '体重',
    HealthMetricKind.bodyFat => '体脂',
    _ => kind.wire,
  };

  static DateTime _dayAnchor(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day, 12);
}
