import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../../core/haptics/haptics.dart';
import '../../../../data/domain/enums.dart';
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
  const PhysicalAssetCreateSheet({super.key, required this.type});

  final AssetType type;

  @override
  ConsumerState<PhysicalAssetCreateSheet> createState() =>
      _PhysicalAssetCreateSheetState();

  static Future<PhysicalAsset?> show(
    BuildContext context, {
    required AssetType type,
  }) {
    return showGlassModalBottomSheet<PhysicalAsset>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: PhysicalAssetCreateSheet(type: type),
      ),
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
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd(
      Localizations.maybeLocaleOf(context)?.toString(),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.s16,
          Spacing.s12,
          Spacing.s16,
          Spacing.s24,
        ),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: Spacing.s12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: Radii.brXs,
                    ),
                  ),
                ),
                Text(
                  _isVehicle
                      ? l10n.physicalAssetAddVehicle
                      : l10n.physicalAssetAddRealEstate,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: Spacing.s16),
                TextFormField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  decoration: InputDecoration(
                    labelText: l10n.physicalAssetFieldName,
                  ),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _isVehicle
                      ? _currencyFocus.requestFocus()
                      : _addressFocus.requestFocus(),
                  validator: _required(l10n),
                ),
                const SizedBox(height: Spacing.s12),
                if (!_isVehicle) ...[
                  TextFormField(
                    controller: _addressCtrl,
                    focusNode: _addressFocus,
                    decoration: InputDecoration(
                      labelText: l10n.physicalAssetFieldAddress,
                    ),
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _currencyFocus.requestFocus(),
                  ),
                  const SizedBox(height: Spacing.s12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _currencyCtrl,
                        focusNode: _currencyFocus,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) =>
                            _purchasePriceFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: l10n.physicalAssetFieldCurrency,
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: _required(l10n),
                      ),
                    ),
                    const SizedBox(width: Spacing.s12),
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
                const SizedBox(height: Spacing.s12),
                TextFormField(
                  controller: _purchasePriceCtrl,
                  focusNode: _purchasePriceFocus,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      _currentValuationFocus.requestFocus(),
                  decoration: InputDecoration(
                    labelText: l10n.physicalAssetFieldPurchasePrice,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _positiveDecimal(l10n),
                ),
                const SizedBox(height: Spacing.s12),
                TextFormField(
                  controller: _currentValuationCtrl,
                  focusNode: _currentValuationFocus,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _isVehicle
                      ? _residualRateFocus.requestFocus()
                      : _linkedLiabilityFocus.requestFocus(),
                  decoration: InputDecoration(
                    labelText: l10n.physicalAssetFieldCurrentValuation,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    return _positiveDecimal(l10n)(v);
                  },
                ),
                if (_isVehicle) ...[
                  const SizedBox(height: Spacing.s12),
                  TextFormField(
                    controller: _residualRateCtrl,
                    focusNode: _residualRateFocus,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _saving ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: l10n.physicalAssetFieldAnnualResidualRate,
                      helperText: '0.85',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
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
                  ),
                  const SizedBox(height: Spacing.s4),
                  SwitchListTile.adaptive(
                    title: Text(l10n.physicalAssetFieldAutoDepreciation),
                    value: _autoDepreciation,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _autoDepreciation = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
                if (!_isVehicle) ...[
                  const SizedBox(height: Spacing.s12),
                  TextFormField(
                    controller: _linkedLiabilityCtrl,
                    focusNode: _linkedLiabilityFocus,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _saving ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: l10n.physicalAssetFieldLinkedLiability,
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.s24),
                FButton(
                  variant: FButtonVariant.primary,
                  onPress: _saving ? null : _submit,
                  child: Text(l10n.physicalAssetCreateSubmit),
                ),
              ],
            ),
          ),
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
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final repo =
          await ref.read(physicalAssetRepositoryProvider.future);
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
              annualResidualRate:
                  Decimal.parse(_residualRateCtrl.text.trim()),
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
      unawaited(ref.read(formDefaultsProvider.notifier).rememberAsset(
            currency: _currencyCtrl.text.trim().toUpperCase(),
          ));
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop(created);
    } finally {
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
