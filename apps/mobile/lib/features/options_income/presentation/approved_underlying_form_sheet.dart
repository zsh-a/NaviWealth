import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../domain/values/asset_market.dart';
import '../../../l10n/gen/app_localizations.dart';
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
  late final TextEditingController _symbolController;
  late AssetMarket _market;
  late bool _allowPut;
  late bool _allowCall;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _symbolController = TextEditingController(
      text: existing?.symbol ?? '',
    );
    _market = existing?.market ?? AssetMarket.usStock;
    _allowPut = existing?.allowPut ?? true;
    _allowCall = existing?.allowCall ?? true;
  }

  @override
  void dispose() {
    _symbolController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final symbol = _symbolController.text.trim();
    if (symbol.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).incomePlannerSymbolRequired,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = await ref.read(
        approvedUnderlyingsRepositoryProvider.future,
      );
      final existing = widget.existing;
      if (existing == null) {
        await repo.add(
          symbol: symbol,
          market: _market,
          allowPut: _allowPut,
          allowCall: _allowCall,
        );
      } else {
        await repo.update(
          existing.copyWith(
            allowPut: _allowPut,
            allowCall: _allowCall,
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
    setState(() => _busy = true);
    try {
      final repo = await ref.read(
        approvedUnderlyingsRepositoryProvider.future,
      );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextFormField(
            control: FTextFieldControl.managed(controller: _symbolController),
            label: Text(l10n.incomePlannerSymbolLabel),
            hint: l10n.incomePlannerSymbolHint,
            enabled: !_isEdit, // symbol is part of the PK; cannot change
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: AppSpacing.s12),
          FSelect<AssetMarket>(
            items: const {
              'US': AssetMarket.usStock,
              'HK': AssetMarket.hkStock,
              'CN A': AssetMarket.cnA,
              'Crypto': AssetMarket.crypto,
            },
            control: FSelectControl<AssetMarket>.managed(
              initial: _market,
              onChange: (value) {
                if (value != null) setState(() => _market = value);
              },
            ),
            label: Text(l10n.incomePlannerMarketLabel),
          ),
          const SizedBox(height: AppSpacing.s16),
          _SwitchRow(
            label: l10n.incomePlannerAllowPutLabel,
            value: _allowPut,
            onChanged: (v) => setState(() => _allowPut = v),
          ),
          _SwitchRow(
            label: l10n.incomePlannerAllowCallLabel,
            value: _allowCall,
            onChanged: (v) => setState(() => _allowCall = v),
          ),
          if (_isEdit) ...[
            const SizedBox(height: AppSpacing.s16),
            FButton(
              variant: FButtonVariant.destructive,
              onPress: _busy ? null : _delete,
              child: Text(l10n.incomePlannerDeleteAction),
            ),
          ],
        ],
      ),
    );
  }
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
          Expanded(
            child: Text(
              label,
              style: context.theme.typography.sm,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          FSwitch(value: value, onChange: onChanged),
        ],
      ),
    );
  }
}
