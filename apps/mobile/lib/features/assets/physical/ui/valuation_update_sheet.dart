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
  const ValuationUpdateSheet({super.key, required this.asset});

  final PhysicalAsset asset;

  @override
  ConsumerState<ValuationUpdateSheet> createState() =>
      _ValuationUpdateSheetState();

  static Future<bool?> show(
    BuildContext context, {
    required PhysicalAsset asset,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ValuationUpdateSheet(asset: asset),
      ),
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
                l10n.physicalAssetUpdateValuationTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Spacing.s16),
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
              const SizedBox(height: Spacing.s12),
              InkWell(
                onTap: _saving ? null : _pickDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.physicalAssetUpdateValuationDate,
                  ),
                  child: Text(dateFormat.format(_asOf)),
                ),
              ),
              const SizedBox(height: Spacing.s12),
              FTextFormField(
                control: FTextFieldControl.managed(controller: _noteCtrl),
                label: Text(l10n.physicalAssetFieldNote),
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: Spacing.s24),
              FButton(
                variant: FButtonVariant.primary,
                onPress: _saving ? null : _submit,
                child: Text(l10n.physicalAssetUpdateValuationSubmit),
              ),
            ],
          ),
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
    if (picked != null) setState(() => _asOf = picked);
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
