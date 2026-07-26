import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/symbol_field.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/providers.dart';
import '../domain/approved_underlying.dart';

/// Add or edit an [ApprovedUnderlying]. When [existing] is provided the
/// sheet is in edit mode; otherwise it adds a new row.
///
/// Returns `true` on save / delete, `null` on cancel.
Future<bool?> showApprovedUnderlyingSheet(
  BuildContext context, {
  ApprovedUnderlying? existing,
}) {
  return showAppFormSheet<bool>(
    context: context,
    builder: (_) => _ApprovedUnderlyingFormSheet(existing: existing),
  );
}

class _ApprovedUnderlyingFormSheet extends ConsumerStatefulWidget {
  const _ApprovedUnderlyingFormSheet({this.existing});

  final ApprovedUnderlying? existing;

  @override
  ConsumerState<_ApprovedUnderlyingFormSheet> createState() =>
      _ApprovedUnderlyingFormSheetState();
}

class _ApprovedUnderlyingFormSheetState
    extends ConsumerState<_ApprovedUnderlyingFormSheet> {
  final _formKey = GlobalKey<FormState>();
  LocalSecurityChoice? _choice;
  late final TextEditingController _maxBuyPriceCtl;
  late final TextEditingController _minSellPriceCtl;
  late final TextEditingController _notesCtl;
  late bool _allowPut;
  late bool _allowCall;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      // Edit mode: symbol is part of the PK so it can't change; seed the
      // field's read-only summary from the row.
      _choice = LocalSecurityChoice(
        symbol: existing.symbol,
        market: existing.market,
        type: AssetType.stock,
        currency: 'USD',
        fromCatalog: true,
      );
    }
    _allowPut = existing?.allowPut ?? true;
    _allowCall = existing?.allowCall ?? true;
    _maxBuyPriceCtl = TextEditingController(
      text: existing?.maxBuyPrice?.toString() ?? '',
    );
    _minSellPriceCtl = TextEditingController(
      text: existing?.minSellPrice?.toString() ?? '',
    );
    _notesCtl = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _maxBuyPriceCtl.dispose();
    _minSellPriceCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final choice = _choice;
    if (choice == null) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).incomePlannerSymbolRequired,
      );
      return;
    }
    if (!_allowPut && !_allowCall) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).incomePlannerUnderlyingStrategyRequired,
      );
      return;
    }
    final maxBuyPrice = _optionalPositiveDecimal(_maxBuyPriceCtl.text);
    final minSellPrice = _optionalPositiveDecimal(_minSellPriceCtl.text);
    final notes = _notesCtl.text.trim();
    setState(() => _busy = true);
    try {
      final repo = await ref.read(approvedUnderlyingsRepositoryProvider.future);
      final existing = widget.existing;
      if (existing == null) {
        await repo.add(
          symbol: choice.symbol,
          market: choice.market,
          allowPut: _allowPut,
          allowCall: _allowCall,
          maxBuyPrice: maxBuyPrice,
          minSellPrice: minSellPrice,
          notes: notes.isEmpty ? null : notes,
        );
      } else {
        await repo.update(
          existing.copyWith(
            allowPut: _allowPut,
            allowCall: _allowCall,
            maxBuyPrice: maxBuyPrice,
            minSellPrice: minSellPrice,
            notes: notes.isEmpty ? null : notes,
          ),
        );
      }
      ref.invalidate(approvedUnderlyingsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).incomePlannerUnderlyingSaveError,
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.incomePlannerUnderlyingDeleteTitle),
      body: Text(
        l10n.incomePlannerUnderlyingDeleteBody(existing.displaySymbol),
      ),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(approvedUnderlyingsRepositoryProvider.future);
      await repo.remove(existing);
      ref.invalidate(approvedUnderlyingsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).incomePlannerUnderlyingSaveError,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: _isEdit
          ? l10n.incomePlannerEditUnderlyingTitle
          : l10n.incomePlannerAddUnderlyingTitle,
      footer: AppSheetFooter(
        submitLabel: l10n.incomePlannerSaveAction,
        cancelLabel: l10n.incomePlannerCancelAction,
        onSubmit: _save,
        busy: _busy,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SymbolField(
              markets: const [AssetMarket.usStock],
              initialValue: _choice,
              readOnly: _isEdit,
              label: l10n.incomePlannerSymbolLabel,
              hint: l10n.incomePlannerSymbolHint,
              onChanged: (c) => setState(() => _choice = c),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.incomePlannerSupportedMarketHelper,
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s16),
            _SwitchRow(
              label: l10n.incomePlannerAllowPutLabel,
              value: _allowPut,
              onChanged: (v) => setState(() => _allowPut = v),
            ),
            AnimatedSizeFade(
              visible: _allowPut,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s8),
                child: _PriceField(
                  controller: _maxBuyPriceCtl,
                  label: l10n.incomePlannerMaxBuyPriceLabel,
                  description: l10n.incomePlannerMaxBuyPriceHelper,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            _SwitchRow(
              label: l10n.incomePlannerAllowCallLabel,
              value: _allowCall,
              onChanged: (v) => setState(() => _allowCall = v),
            ),
            AnimatedSizeFade(
              visible: _allowCall,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s8),
                child: _PriceField(
                  controller: _minSellPriceCtl,
                  label: l10n.incomePlannerMinSellPriceLabel,
                  description: l10n.incomePlannerMinSellPriceHelper,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _notesCtl),
              label: Text(l10n.incomePlannerUnderlyingNotesLabel),
              description: Text(l10n.incomePlannerUnderlyingNotesHelper),
              maxLines: 3,
            ),
            if (_isEdit) ...[
              const SizedBox(height: AppSpacing.s24),
              FButton(
                variant: FButtonVariant.destructive,
                onPress: _busy ? null : _delete,
                child: Text(l10n.incomePlannerDeleteAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.controller,
    required this.label,
    required this.description,
  });

  final TextEditingController controller;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FTextFormField(
      control: FTextFieldControl.managed(controller: controller),
      label: Text(label),
      description: Text(description),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      validator: (value) {
        final raw = (value ?? '').trim();
        if (raw.isEmpty) return null;
        final parsed = Decimal.tryParse(raw);
        if (parsed == null || parsed <= Decimal.zero) {
          return l10n.incomePlannerPositiveNumberValidation;
        }
        return null;
      },
    );
  }
}

Decimal? _optionalPositiveDecimal(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return null;
  return Decimal.tryParse(raw);
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.theme.typography.body.sm)),
          const SizedBox(width: AppSpacing.s12),
          FSwitch(value: value, onChange: onChanged),
        ],
      ),
    );
  }
}
