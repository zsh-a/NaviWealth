import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/options_strategy_profile.dart';
import 'income_planner_labels.dart';

/// Edit-or-create the strategy profile. Returns `true` on save.
Future<bool> showStrategyProfileSheet(BuildContext context) async {
  final result = await showAppFormSheet<bool>(
    context: context,
    builder: (_) => const _StrategyProfileSheet(),
  );
  return result ?? false;
}

class _StrategyProfileSheet extends ConsumerStatefulWidget {
  const _StrategyProfileSheet();

  @override
  ConsumerState<_StrategyProfileSheet> createState() =>
      _StrategyProfileSheetState();
}

class _StrategyProfileSheetState extends ConsumerState<_StrategyProfileSheet> {
  OptionsStrategyProfile? _draft;
  bool _busy = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final asyncProfile = ref.read(optionsStrategyProfileProvider);
    _draft = asyncProfile.maybeWhen(
      data: (p) => p ?? defaultProfileForMode(OptionsStrategyMode.balanced),
      orElse: () => defaultProfileForMode(OptionsStrategyMode.balanced),
    );
  }

  void _setMode(OptionsStrategyMode mode) {
    final next = defaultProfileForMode(mode).copyWith(
      // Preserve the disclosure ack across mode switches — re-presenting
      // the OCC ODD just because the user toggled Balanced → Aggressive
      // is hostile.
      riskDisclosureAckAt: _draft?.riskDisclosureAckAt,
    );
    setState(() => _draft = next);
  }

  void _toggleAllowed(OptionsStrategyKind kind, bool enabled) {
    final draft = _draft;
    if (draft == null) return;
    final next = {...draft.allowedStrategies};
    if (enabled) {
      next.add(kind);
    } else {
      next.remove(kind);
    }
    setState(() {
      _draft = draft.copyWith(
        allowedStrategies: next,
        mode: OptionsStrategyMode.custom,
      );
    });
  }

  void _toggleAvoidEarnings(bool value) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _draft = draft.copyWith(
        avoidEarnings: value,
        mode: OptionsStrategyMode.custom,
      );
    });
  }

  void _toggleAvoidMacroEvents(bool value) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _draft = draft.copyWith(
        avoidMacroEvents: value,
        mode: OptionsStrategyMode.custom,
      );
    });
  }

  void _toggleOnlyApproved(bool value) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _draft = draft.copyWith(
        onlyOnApprovedUnderlyings: value,
        mode: OptionsStrategyMode.custom,
      );
    });
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(
        optionsStrategyProfileRepositoryProvider.future,
      );
      await repo.upsert(draft);
      ref.invalidate(optionsStrategyProfileProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).incomePlannerProfileSaveError,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = _draft;
    if (draft == null) {
      return AppSheet(
        title: l10n.incomePlannerProfileTitle,
        child: const SizedBox(height: AppSpacing.s40 * 2),
      );
    }
    return AppSheet(
      title: l10n.incomePlannerProfileTitle,
      footer: AppSheetFooter(
        submitLabel: l10n.incomePlannerProfileSave,
        cancelLabel: l10n.incomePlannerProfileCancel,
        onSubmit: _save,
        busy: _busy,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FSelect<OptionsStrategyMode>(
            items: {
              for (final mode in OptionsStrategyMode.values)
                optionsStrategyModeLabel(l10n, mode): mode,
            },
            control: FSelectControl<OptionsStrategyMode>.managed(
              initial: draft.mode,
              onChange: (value) {
                if (value != null) _setMode(value);
              },
            ),
            label: Text(l10n.incomePlannerProfileMode),
          ),
          const SizedBox(height: AppSpacing.s16),
          _SectionLabel(l10n.incomePlannerProfileAllowedStrategies),
          const SizedBox(height: AppSpacing.s8),
          _SwitchRow(
            label: l10n.incomePlannerProfileAllowPut,
            value: draft.allowedStrategies.contains(
              OptionsStrategyKind.cashSecuredPut,
            ),
            onChanged: (v) =>
                _toggleAllowed(OptionsStrategyKind.cashSecuredPut, v),
          ),
          _SwitchRow(
            label: l10n.incomePlannerProfileAllowCall,
            value: draft.allowedStrategies.contains(
              OptionsStrategyKind.coveredCall,
            ),
            onChanged: (v) =>
                _toggleAllowed(OptionsStrategyKind.coveredCall, v),
          ),
          const SizedBox(height: AppSpacing.s12),
          _SwitchRow(
            label: l10n.incomePlannerProfileAvoidEarnings,
            value: draft.avoidEarnings,
            onChanged: _toggleAvoidEarnings,
          ),
          _SwitchRow(
            label: l10n.incomePlannerProfileAvoidMacroEvents,
            value: draft.avoidMacroEvents,
            onChanged: _toggleAvoidMacroEvents,
          ),
          _SwitchRow(
            label: l10n.incomePlannerProfileOnlyApproved,
            value: draft.onlyOnApprovedUnderlyings,
            onChanged: _toggleOnlyApproved,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Text(text, style: context.labelStyle),
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
          Expanded(child: Text(label, style: context.theme.typography.sm)),
          const SizedBox(width: AppSpacing.s12),
          FSwitch(value: value, onChange: onChanged),
        ],
      ),
    );
  }
}
