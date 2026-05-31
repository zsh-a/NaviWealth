import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../../core/haptics/haptics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../shared/forms/forms.dart';
import '../data/physical_asset.dart';
import '../data/providers.dart';

class ValuationUpdateSheet extends ConsumerStatefulWidget {
  const ValuationUpdateSheet({
    super.key,
    required this.asset,
    required this.dirty,
  });

  final PhysicalAsset asset;
  final FormDirtyController dirty;

  @override
  ConsumerState<ValuationUpdateSheet> createState() =>
      _ValuationUpdateSheetState();

  static Future<bool?> show(
    BuildContext context, {
    required PhysicalAsset asset,
  }) {
    return showGuardedFormSheet<bool>(
      context: context,
      builder: (_, dirty) => ValuationUpdateSheet(asset: asset, dirty: dirty),
    );
  }
}

class _ValuationUpdateSheetState extends ConsumerState<ValuationUpdateSheet>
    with OptimisticFormSubmit<ValuationUpdateSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  final TextEditingController _noteCtrl = TextEditingController();
  late DateTime _asOf;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: widget.asset.currentValuation.toString(),
    );
    _asOf = DateTime.now();
    // `_amountCtrl` is seeded from the current valuation — that baseline
    // is not a user edit.
    widget.dirty.bindTextControllers([_amountCtrl, _noteCtrl]);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateFormat = DateFormat.yMMMd(
      Localizations.maybeLocaleOf(context)?.toString(),
    );
    return AppSheet(
      title: l10n.physicalAssetUpdateValuationTitle,
      footer: AppSheetFooter(
        submitLabel: l10n.physicalAssetUpdateValuationSubmit,
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
            FTextFormField(
              control: FTextFieldControl.managed(controller: _amountCtrl),
              label: Text(l10n.physicalAssetUpdateValuationAmount),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return l10n.physicalAssetValidationRequired;
                }
                final parsed = Decimal.tryParse(v.trim());
                if (parsed == null || parsed < Decimal.zero) {
                  return l10n.physicalAssetValidationPositive;
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            GestureDetector(
              onTap: _saving ? null : _pickDate,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.physicalAssetUpdateValuationDate,
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    dateFormat.format(_asOf),
                    style: context.theme.typography.sm,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _noteCtrl),
              label: Text(l10n.physicalAssetFieldNote),
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
      initialDate: _asOf,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _asOf = picked;
        widget.dirty.markDirty();
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final repo = await ref.read(physicalAssetRepositoryProvider.future);
    if (!mounted) return;

    final assetId = widget.asset.id;
    final amount = Decimal.parse(_amountCtrl.text.trim());
    final asOf = _asOf;
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

    // The record is being persisted — the post-save pop must not prompt.
    widget.dirty.markPristine();
    await submitOptimistic(
      pop: () {
        Haptics.success();
        Navigator.of(context).pop(true);
      },
      tag: 'valuation',
      failureMessage: (_) => l10n.commonSaveFailed,
      retryLabel: l10n.commonRetry,
      write: () => repo.updateValuation(
        assetId: assetId,
        newValuation: amount,
        asOf: asOf,
        note: note,
      ),
    );
  }
}
