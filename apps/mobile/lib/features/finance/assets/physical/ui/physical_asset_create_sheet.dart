import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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

  // Core focus chain: name → currency → purchase price. Optional details
  // continue through address/depreciation and valuation fields.
  final _nameFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _currencyFocus = FocusNode();
  final _purchasePriceFocus = FocusNode();
  final _currentValuationFocus = FocusNode();
  final _residualRateFocus = FocusNode();
  final _linkedLiabilityFocus = FocusNode();
  final _detailsFocus = FocusNode(debugLabel: 'physical-asset-details');

  DateTime _purchaseDate = DateTime.now();
  bool _autoDepreciation = true;
  bool _detailsExpanded = false;
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
    _detailsFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              key: const Key('physical-asset-name-field'),
              control: FTextFieldControl.managed(controller: _nameCtrl),
              label: RequiredLabel(l10n.physicalAssetFieldName),
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              validator: _required(l10n),
              onSubmit: (_) => _currencyFocus.requestFocus(),
            ),
            const SizedBox(height: AppSpacing.s12),
            ResponsiveTwoColumn(
              breakpoint: 520,
              gap: AppSpacing.s12,
              left: FTextFormField(
                key: const Key('physical-asset-currency-field'),
                control: FTextFieldControl.managed(controller: _currencyCtrl),
                label: RequiredLabel(l10n.physicalAssetFieldCurrency),
                focusNode: _currencyFocus,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.characters,
                validator: _required(l10n),
                onSubmit: (_) => _purchasePriceFocus.requestFocus(),
              ),
              right: DateField(
                key: const Key('physical-asset-purchase-date-field'),
                label: l10n.physicalAssetFieldPurchaseDate,
                initialValue: _purchaseDate,
                firstDate: DateTime(1970),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                required: true,
                enabled: !_saving,
                onChanged: (picked) {
                  if (picked == null) return;
                  setState(() {
                    _purchaseDate = picked;
                    widget.dirty.markDirty();
                  });
                },
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              key: const Key('physical-asset-purchase-price-field'),
              control: FTextFieldControl.managed(
                controller: _purchasePriceCtrl,
              ),
              label: RequiredLabel(l10n.physicalAssetFieldPurchasePrice),
              focusNode: _purchasePriceFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              validator: _positiveDecimal(l10n),
              onSubmit: (_) {
                _purchasePriceFocus.unfocus();
                if (!_detailsExpanded) {
                  setState(() => _detailsExpanded = true);
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _detailsFocus.requestFocus();
                });
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            FAccordion(
              control: FAccordionControl.lifted(
                expanded: (_) => _detailsExpanded,
                onChange: (_, expanded) =>
                    setState(() => _detailsExpanded = expanded),
              ),
              children: [
                FAccordionItem(
                  key: const Key('physical-asset-details-disclosure'),
                  focusNode: _detailsFocus,
                  title: Semantics(
                    key: const Key('physical-asset-details-toggle-label'),
                    expanded: _detailsExpanded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.physicalAssetDetailsTitle),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          _isVehicle
                              ? l10n.physicalAssetVehicleDetailsSummary
                              : l10n.physicalAssetRealEstateDetailsSummary,
                          style: context.captionStyle,
                        ),
                      ],
                    ),
                  ),
                  child: Offstage(
                    key: const Key('physical-asset-details-fields'),
                    offstage: !_detailsExpanded,
                    child: ExcludeFocus(
                      excluding: !_detailsExpanded,
                      child: ExcludeSemantics(
                        excluding: !_detailsExpanded,
                        child: Column(
                          children: [
                            if (!_isVehicle) ...[
                              FTextFormField(
                                key: const Key('physical-asset-address-field'),
                                control: FTextFieldControl.managed(
                                  controller: _addressCtrl,
                                ),
                                label: Text(l10n.physicalAssetFieldAddress),
                                focusNode: _addressFocus,
                                textInputAction: TextInputAction.next,
                                onSubmit: (_) =>
                                    _currentValuationFocus.requestFocus(),
                              ),
                              const SizedBox(height: AppSpacing.s12),
                            ],
                            FTextFormField(
                              key: const Key(
                                'physical-asset-current-valuation-field',
                              ),
                              control: FTextFieldControl.managed(
                                controller: _currentValuationCtrl,
                              ),
                              label: Text(
                                l10n.physicalAssetFieldCurrentValuation,
                              ),
                              focusNode: _currentValuationFocus,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                              const SizedBox(height: AppSpacing.s12),
                              FTextFormField(
                                key: const Key(
                                  'physical-asset-residual-rate-field',
                                ),
                                control: FTextFieldControl.managed(
                                  controller: _residualRateCtrl,
                                ),
                                label: RequiredLabel(
                                  l10n.physicalAssetFieldAnnualResidualRate,
                                ),
                                description: const Text('0.85'),
                                focusNode: _residualRateFocus,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
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
                                    return l10n
                                        .physicalAssetValidationResidualRange;
                                  }
                                  return null;
                                },
                                onSubmit: (_) => _saving ? null : _submit(),
                              ),
                              const SizedBox(height: AppSpacing.s12),
                              FSwitch(
                                label: Text(
                                  l10n.physicalAssetFieldAutoDepreciation,
                                ),
                                value: _autoDepreciation,
                                enabled: !_saving,
                                onChange: (v) => setState(() {
                                  _autoDepreciation = v;
                                  widget.dirty.markDirty();
                                }),
                              ),
                            ] else ...[
                              const SizedBox(height: AppSpacing.s12),
                              FTextFormField(
                                key: const Key(
                                  'physical-asset-linked-liability-field',
                                ),
                                control: FTextFieldControl.managed(
                                  controller: _linkedLiabilityCtrl,
                                ),
                                label: Text(
                                  l10n.physicalAssetFieldLinkedLiability,
                                ),
                                focusNode: _linkedLiabilityFocus,
                                textInputAction: TextInputAction.done,
                                onSubmit: (_) => _saving ? null : _submit(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      if (!_detailsAreValid && !_detailsExpanded) {
        setState(() => _detailsExpanded = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _detailsFocus.requestFocus();
        });
      }
      return;
    }
    final l10n = AppLocalizations.of(context);
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
      AppInteraction.signal(AppInteractionIntent.success);
      Navigator.of(context).pop(created);
    } catch (_) {
      if (!mounted) return;
      AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
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

  bool get _detailsAreValid {
    final valuationText = _currentValuationCtrl.text.trim();
    if (valuationText.isNotEmpty) {
      final valuation = Decimal.tryParse(valuationText);
      if (valuation == null || valuation <= Decimal.zero) return false;
    }
    if (!_isVehicle) return true;
    final residualRate = Decimal.tryParse(_residualRateCtrl.text.trim());
    return residualRate != null &&
        residualRate > Decimal.zero &&
        residualRate < Decimal.one;
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
