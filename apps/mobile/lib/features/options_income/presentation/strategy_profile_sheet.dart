import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/options_strategy_profile.dart';
import 'income_planner_strings.dart';

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

class _StrategyProfileSheetState
    extends ConsumerState<_StrategyProfileSheet> {
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
        IncomePlannerStrings.profileSaveError,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft == null) {
      return const AppSheet(
        title: IncomePlannerStrings.profileTitle,
        child: SizedBox(height: 80),
      );
    }
    return AppSheet(
      title: IncomePlannerStrings.profileTitle,
      footer: AppSheetFooter(
        submitLabel: IncomePlannerStrings.profileSave,
        cancelLabel: IncomePlannerStrings.profileCancel,
        onSubmit: _save,
        busy: _busy,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FSelect<OptionsStrategyMode>(
            items: const {
              IncomePlannerStrings.profileModeConservative:
                  OptionsStrategyMode.conservative,
              IncomePlannerStrings.profileModeBalanced:
                  OptionsStrategyMode.balanced,
              IncomePlannerStrings.profileModeAggressive:
                  OptionsStrategyMode.aggressive,
              IncomePlannerStrings.profileModeCustom:
                  OptionsStrategyMode.custom,
            },
            control: FSelectControl<OptionsStrategyMode>.managed(
              initial: draft.mode,
              onChange: (value) {
                if (value != null) _setMode(value);
              },
            ),
            label: const Text(IncomePlannerStrings.profileMode),
          ),
          const SizedBox(height: AppSpacing.s16),
          const _SectionLabel(IncomePlannerStrings.profileAllowedStrategies),
          const SizedBox(height: AppSpacing.s8),
          _SwitchRow(
            label: IncomePlannerStrings.profileAllowPut,
            value: draft.allowedStrategies
                .contains(OptionsStrategyKind.cashSecuredPut),
            onChanged: (v) =>
                _toggleAllowed(OptionsStrategyKind.cashSecuredPut, v),
          ),
          _SwitchRow(
            label: IncomePlannerStrings.profileAllowCall,
            value: draft.allowedStrategies
                .contains(OptionsStrategyKind.coveredCall),
            onChanged: (v) =>
                _toggleAllowed(OptionsStrategyKind.coveredCall, v),
          ),
          const SizedBox(height: AppSpacing.s12),
          _SwitchRow(
            label: IncomePlannerStrings.profileAvoidEarnings,
            value: draft.avoidEarnings,
            onChanged: _toggleAvoidEarnings,
          ),
          _SwitchRow(
            label: IncomePlannerStrings.profileAvoidMacroEvents,
            value: draft.avoidMacroEvents,
            onChanged: _toggleAvoidMacroEvents,
          ),
          _SwitchRow(
            label: IncomePlannerStrings.profileOnlyApproved,
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
      child: Text(
        text,
        style: context.theme.typography.sm.copyWith(
          fontWeight: FontWeight.w600,
        ),
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
          FSwitch(
            value: value,
            onChange: onChanged,
          ),
        ],
      ),
    );
  }
}
