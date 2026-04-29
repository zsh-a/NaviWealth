import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../data/domain/enums.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
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
    return showModalBottomSheet<PhysicalAsset>(
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

  DateTime _purchaseDate = DateTime.now();
  bool _autoDepreciation = true;
  bool _saving = false;

  bool get _isVehicle => widget.type == AssetType.vehicle;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _currentValuationCtrl.dispose();
    _residualRateCtrl.dispose();
    _linkedLiabilityCtrl.dispose();
    _currencyCtrl.dispose();
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
          child: SingleChildScrollView(
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
                  decoration: InputDecoration(
                    labelText: l10n.physicalAssetFieldName,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _required(l10n),
                ),
                const SizedBox(height: Spacing.s12),
                if (!_isVehicle) ...[
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.physicalAssetFieldAddress,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: Spacing.s12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _currencyCtrl,
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
                    decoration: InputDecoration(
                      labelText: l10n.physicalAssetFieldLinkedLiability,
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.s24),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.physicalAssetCreateSubmit),
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
      if (!mounted) return;
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
