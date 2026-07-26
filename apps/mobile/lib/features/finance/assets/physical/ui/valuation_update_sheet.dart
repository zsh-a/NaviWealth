import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
    with FormSubmission<ValuationUpdateSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  final TextEditingController _noteCtrl = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _noteFocus = FocusNode();
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
    _amountFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (submissionFailureMessage != null) ...[
              AppStatusBanner(
                kind: AppStatusKind.error,
                message: submissionFailureMessage!,
                compact: true,
              ),
              const SizedBox(height: AppSpacing.s12),
            ],
            FTextFormField(
              key: const Key('valuation-update-amount-field'),
              control: FTextFieldControl.managed(controller: _amountCtrl),
              label: RequiredLabel(l10n.physicalAssetUpdateValuationAmount),
              focusNode: _amountFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
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
              onSubmit: (_) => _noteFocus.requestFocus(),
            ),
            const SizedBox(height: AppSpacing.s12),
            DateField(
              label: l10n.physicalAssetUpdateValuationDate,
              initialValue: _asOf,
              firstDate: DateTime(1970),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              required: true,
              enabled: !_saving,
              onChanged: (picked) {
                if (picked == null) return;
                setState(() {
                  _asOf = picked;
                  widget.dirty.markDirty();
                });
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              key: const Key('valuation-update-note-field'),
              control: FTextFieldControl.managed(controller: _noteCtrl),
              label: Text(l10n.physicalAssetFieldNote),
              focusNode: _noteFocus,
              textInputAction: TextInputAction.done,
              onSubmit: (_) => _saving ? null : _submit(),
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
    final l10n = AppLocalizations.of(context);

    final assetId = widget.asset.id;
    final amount = Decimal.parse(_amountCtrl.text.trim());
    final asOf = _asOf;
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      leave: () => Navigator.of(context).pop(true),
      tag: 'valuation',
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.commonSaved,
      commit: () async {
        final repo = await ref.read(physicalAssetRepositoryProvider.future);
        await repo.updateValuation(
          assetId: assetId,
          newValuation: amount,
          asOf: asOf,
          note: note,
        );
      },
    );
  }

  void _setSaving(bool value) {
    if (mounted && _saving != value) setState(() => _saving = value);
  }
}
