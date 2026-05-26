import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';

import '../../../../core/haptics/haptics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../shared/forms/forms.dart';
import '../data/physical_asset.dart';
import '../data/providers.dart';

/// Modal sheet for creating a new real-estate or vehicle asset.
///
/// Returns the created [PhysicalAsset] via `Navigator.pop` so the caller
/// can navigate to its detail page; returns `null` if the user cancels.
class PhysicalAssetCreateSheet extends ConsumerStatefulWidget {
  const PhysicalAssetCreateSheet({
    super.key,
    required this.type,
    required this.dirty,
  });

  final AssetType type;
  final FormDirtyController dirty;

  @override
  ConsumerState<PhysicalAssetCreateSheet> createState() =>
      _PhysicalAssetCreateSheetState();

  static Future<PhysicalAsset?> show(
    BuildContext context, {
    required AssetType type,
  }) {
    return showGuardedFormSheet<PhysicalAsset>(
      context: context,
      builder: (_, dirty) => PhysicalAssetCreateSheet(type: type, dirty: dirty),
    );
  }
}

class _PhysicalAssetCreateSheetState
    extends ConsumerState<PhysicalAssetCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _purchasePriceCtrl = TextEditingController();
  final _currentValuationCtrl = TextEditingController();
  final _residualRateCtrl = TextEditingController(text: '0.85');
  final _linkedLiabilityCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'CNY');

  // Focus chain (real estate): name → address → currency → purchasePrice
  // → currentValuation → linkedLiability.
  // Focus chain (vehicle):     name → currency → purchasePrice
  // → currentValuation → residualRate.
  final _nameFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _currencyFocus = FocusNode();
  final _purchasePriceFocus = FocusNode();
  final _currentValuationFocus = FocusNode();
  final _residualRateFocus = FocusNode();
  final _linkedLiabilityFocus = FocusNode();

  DateTime _purchaseDate = DateTime.now();
  bool _autoDepreciation = true;
  bool _saving = false;

  bool get _isVehicle => widget.type == AssetType.vehicle;

  @override
  void initState() {
    super.initState();
    final defaults = ref.read(formDefaultsProvider);
    if (defaults.assetCurrency != null && defaults.assetCurrency!.isNotEmpty) {
      _currencyCtrl.text = defaults.assetCurrency!;
    }
    // Bind after the currency/residual-rate seeds so they are the
    // baseline, not a user edit.
    widget.dirty.bindTextControllers([
      _nameCtrl,
      _addressCtrl,
      _purchasePriceCtrl,
      _currentValuationCtrl,
      _residualRateCtrl,
      _linkedLiabilityCtrl,
      _currencyCtrl,
    ]);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _currentValuationCtrl.dispose();
    _residualRateCtrl.dispose();
    _linkedLiabilityCtrl.dispose();
    _currencyCtrl.dispose();
    _nameFocus.dispose();
    _addressFocus.dispose();
    _currencyFocus.dispose();
    _purchasePriceFocus.dispose();
    _currentValuationFocus.dispose();
    _residualRateFocus.dispose();
    _linkedLiabilityFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateFormat = DateFormat.yMMMd(
      Localizations.maybeLocaleOf(context)?.toString(),
    );
    return AppSheet(
      title: _isVehicle
          ? l10n.physicalAssetAddVehicle
          : l10n.physicalAssetAddRealEstate,
      footer: AppSheetFooter(
        submitLabel: l10n.physicalAssetCreateSubmit,
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
            FTextFormField(
              control: FTextFieldControl.managed(controller: _nameCtrl),
              label: Text(l10n.physicalAssetFieldName),
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              validator: _required(l10n),
              onSubmit: (_) => _isVehicle
                  ? _currencyFocus.requestFocus()
                  : _addressFocus.requestFocus(),
            ),
            const SizedBox(height: 12),
            if (!_isVehicle) ...[
              FTextFormField(
                control: FTextFieldControl.managed(controller: _addressCtrl),
                label: Text(l10n.physicalAssetFieldAddress),
                focusNode: _addressFocus,
                textInputAction: TextInputAction.next,
                onSubmit: (_) => _currencyFocus.requestFocus(),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: FTextFormField(
                    control: FTextFieldControl.managed(
                      controller: _currencyCtrl,
                    ),
                    label: Text(l10n.physicalAssetFieldCurrency),
                    focusNode: _currencyFocus,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.characters,
                    validator: _required(l10n),
                    onSubmit: (_) => _purchasePriceFocus.requestFocus(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _saving ? null : _pickPurchaseDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.physicalAssetFieldPurchaseDate,
                      ),
                      child: Text(dateFormat.format(_purchaseDate)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FTextFormField(
              control: FTextFieldControl.managed(
                controller: _purchasePriceCtrl,
              ),
              label: Text(l10n.physicalAssetFieldPurchasePrice),
              focusNode: _purchasePriceFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              validator: _positiveDecimal(l10n),
              onSubmit: (_) => _currentValuationFocus.requestFocus(),
            ),
            const SizedBox(height: 12),
            FTextFormField(
              control: FTextFieldControl.managed(
                controller: _currentValuationCtrl,
              ),
              label: Text(l10n.physicalAssetFieldCurrentValuation),
              focusNode: _currentValuationFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                return _positiveDecimal(l10n)(v);
              },
              onSubmit: (_) => _isVehicle
                  ? _residualRateFocus.requestFocus()
                  : _linkedLiabilityFocus.requestFocus(),
            ),
            if (_isVehicle) ...[
              const SizedBox(height: 12),
              FTextFormField(
                control: FTextFieldControl.managed(
                  controller: _residualRateCtrl,
                ),
                label: Text(l10n.physicalAssetFieldAnnualResidualRate),
                description: const Text('0.85'),
                focusNode: _residualRateFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return l10n.physicalAssetValidationRequired;
                  }
                  final parsed = Decimal.tryParse(v);
                  if (parsed == null ||
                      parsed <= Decimal.zero ||
                      parsed >= Decimal.one) {
                    return l10n.physicalAssetValidationResidualRange;
                  }
                  return null;
                },
                onSubmit: (_) => _saving ? null : _submit(),
              ),
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                title: Text(l10n.physicalAssetFieldAutoDepreciation),
                value: _autoDepreciation,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                        _autoDepreciation = v;
                        widget.dirty.markDirty();
                      }),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            if (!_isVehicle) ...[
              const SizedBox(height: 12),
              FTextFormField(
                control: FTextFieldControl.managed(
                  controller: _linkedLiabilityCtrl,
                ),
                label: Text(l10n.physicalAssetFieldLinkedLiability),
                focusNode: _linkedLiabilityFocus,
                textInputAction: TextInputAction.done,
                onSubmit: (_) => _saving ? null : _submit(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickPurchaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _purchaseDate = picked;
        widget.dirty.markDirty();
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(physicalAssetRepositoryProvider.future);
      final purchasePrice = Decimal.parse(_purchasePriceCtrl.text.trim());
      final currentValuation = _currentValuationCtrl.text.trim().isEmpty
          ? null
          : Decimal.parse(_currentValuationCtrl.text.trim());
      final created = _isVehicle
          ? await repo.createVehicle(
              name: _nameCtrl.text.trim(),
              currency: _currencyCtrl.text.trim().toUpperCase(),
              purchaseDate: _purchaseDate,
              purchasePrice: purchasePrice,
              currentValuation: currentValuation,
              annualResidualRate: Decimal.parse(_residualRateCtrl.text.trim()),
              autoDepreciation: _autoDepreciation,
            )
          : await repo.createRealEstate(
              name: _nameCtrl.text.trim(),
              address: _addressCtrl.text.trim().isEmpty
                  ? null
                  : _addressCtrl.text.trim(),
              currency: _currencyCtrl.text.trim().toUpperCase(),
              purchaseDate: _purchaseDate,
              purchasePrice: purchasePrice,
              currentValuation: currentValuation,
              linkedLiabilityId: _linkedLiabilityCtrl.text.trim().isEmpty
                  ? null
                  : _linkedLiabilityCtrl.text.trim(),
            );
      unawaited(
        ref
            .read(formDefaultsProvider.notifier)
            .rememberAsset(currency: _currencyCtrl.text.trim().toUpperCase()),
      );
      if (!mounted) return;
      widget.dirty.markPristine();
      Haptics.success();
      Navigator.of(context).pop(created);
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  FormFieldValidator<String> _required(AppLocalizations l10n) {
    return (v) {
      if (v == null || v.trim().isEmpty) {
        return l10n.physicalAssetValidationRequired;
      }
      return null;
    };
  }

  FormFieldValidator<String> _positiveDecimal(AppLocalizations l10n) {
    return (v) {
      if (v == null || v.trim().isEmpty) {
        return l10n.physicalAssetValidationRequired;
      }
      final parsed = Decimal.tryParse(v.trim());
      if (parsed == null || parsed <= Decimal.zero) {
        return l10n.physicalAssetValidationPositive;
      }
      return null;
    };
  }
}
