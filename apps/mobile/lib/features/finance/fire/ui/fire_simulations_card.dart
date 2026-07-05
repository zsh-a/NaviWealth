import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/visual/ai_hover_overlay.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/fire_providers.dart';
import '../domain/fire_state.dart';
import '../domain/fire_state_service.dart';
import 'fire_ai_capsule.dart';
import 'fire_status_colors.dart';

/// Simulations section — preset chips that show how a single plan
/// change would move the headline metrics, without persisting
/// anything. Mirrors `docs/roadmap-fire-os.md` §6 ("Simulations:
/// 支出变化 / 收益率变化 / 半退休收入 / 旅行预算") and shares the same
/// pure helper [simulateFireState] the AI's `simulate_fire_plan` tool
/// uses, so the "Press the chip yourself" path and the
/// "Ask the AI to simulate it" path stay byte-identical.
class FireSimulationsCard extends ConsumerStatefulWidget {
  const FireSimulationsCard({super.key});

  @override
  ConsumerState<FireSimulationsCard> createState() =>
      _FireSimulationsCardState();
}

class _FireSimulationsCardState extends ConsumerState<FireSimulationsCard> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stateAsync = ref.watch(fireStateProvider);
    return AiHoverOverlay(
      capsule: FireAiCapsule(
        intent: 'simulate_fire_change',
        source: 'fire_simulations_card',
        objectType: 'fire_plan',
        objectLabel: l10n.fireOsSimulationsTitle,
      ),
      child: SoftCard(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: stateAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Text(
            '$e',
            style: context.captionStyle.copyWith(
              color: context.theme.colors.destructive,
            ),
          ),
          data: (baseline) => _Body(
            baseline: baseline,
            selected: _selected,
            onSelect: (i) => setState(() => _selected = i),
            l10n: l10n,
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.baseline,
    required this.selected,
    required this.onSelect,
    required this.l10n,
  });

  final FireState baseline;
  final int selected;
  final ValueChanged<int> onSelect;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final presets = _presetsFor(l10n);
    final results = [for (final p in presets) p.apply(baseline)];
    final preset = presets[selected];
    final result = results[selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.fireOsSimulationsTitle,
          style: context.theme.typography.body.md,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(l10n.fireOsSimulationsSubtitle, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s12),
        Wrap(
          spacing: AppSpacing.s6,
          runSpacing: AppSpacing.s6,
          children: [
            for (var i = 0; i < presets.length; i++)
              _PresetChip(
                label: presets[i].label,
                selected: selected == i,
                onTap: () => onSelect(i),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        _DeltaPanel(
          baseline: baseline,
          result: result,
          presetLabel: preset.label,
          l10n: l10n,
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final bg = selected ? colors.primary : Colors.transparent;
    final fg = selected ? colors.primaryForeground : colors.foreground;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: context.captionLabelStyle.copyWith(color: fg),
        ),
      ),
    );
  }
}

class _DeltaPanel extends StatelessWidget {
  const _DeltaPanel({
    required this.baseline,
    required this.result,
    required this.presetLabel,
    required this.l10n,
  });

  final FireState baseline;
  final FireState result;
  final String presetLabel;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final wrLabel = _wrDelta(
      l10n,
      baseline.withdrawalRate,
      result.withdrawalRate,
    );
    final cashLabel = _cashDelta(
      l10n,
      baseline.cashBucketMonths,
      result.cashBucketMonths,
    );
    final safetyChanged = baseline.safetyLevel != result.safetyLevel;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: context.theme.colors.muted.withValues(alpha: AppOpacity.muted),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(presetLabel, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s6),
          Wrap(
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s4,
            children: [
              Text(wrLabel, style: context.captionStyle),
              Text(cashLabel, style: context.captionStyle),
              if (safetyChanged)
                Text(
                  '${baseline.safetyLevel.name} → ${result.safetyLevel.name}',
                  style: context.captionLabelStyle.copyWith(
                    color: fireSafetyColor(
                      SemanticColors.of(context),
                      result.safetyLevel,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _wrDelta(AppLocalizations l10n, double before, double after) {
    if (!before.isFinite || !after.isFinite) {
      return l10n.fireOsSimulationsDeltaWrUnavailable;
    }
    final ppDelta = (after - before) * 100;
    final sign = ppDelta == 0
        ? ''
        : ppDelta > 0
        ? '+'
        : '−';
    return l10n.fireOsSimulationsDeltaWrPp(
      sign,
      ppDelta.abs().toStringAsFixed(2),
    );
  }

  static String _cashDelta(AppLocalizations l10n, double before, double after) {
    if (!before.isFinite || !after.isFinite) {
      return l10n.fireOsSimulationsDeltaCashUnavailable;
    }
    final delta = after - before;
    final sign = delta == 0
        ? ''
        : delta > 0
        ? '+'
        : '−';
    return l10n.fireOsSimulationsDeltaCash(
      sign,
      delta.abs().toStringAsFixed(1),
    );
  }
}

class _Preset {
  const _Preset({required this.label, required this.apply});
  final String label;
  final FireState Function(FireState baseline) apply;
}

List<_Preset> _presetsFor(AppLocalizations l10n) => <_Preset>[
  _Preset(label: l10n.fireOsSimulationsBaselineLabel, apply: (b) => b),
  _Preset(
    label: l10n.fireOsSimulationsPresetExpenseUp20,
    apply: (b) {
      final factor = Decimal.parse('1.2000');
      return simulateFireState(
        baseline: b,
        monthlyExpenses: b.plan.monthlyExpenses * factor,
        trailingScale: 1.2,
      );
    },
  ),
  _Preset(
    label: l10n.fireOsSimulationsPresetExpenseDown10,
    apply: (b) {
      final factor = Decimal.parse('0.9000');
      return simulateFireState(
        baseline: b,
        monthlyExpenses: b.plan.monthlyExpenses * factor,
        trailingScale: 0.9,
      );
    },
  ),
  _Preset(
    label: l10n.fireOsSimulationsPresetSurplusUp30,
    apply: (b) => simulateFireState(
      baseline: b,
      monthlySurplus: b.plan.monthlySurplus * Decimal.parse('1.3000'),
    ),
  ),
  _Preset(
    label: l10n.fireOsSimulationsPresetHalfRetireIncome,
    apply: (b) => simulateFireState(
      baseline: b,
      monthlySurplus: b.plan.monthlySurplus + Decimal.fromInt(5000),
    ),
  ),
  _Preset(
    label: l10n.fireOsSimulationsPresetInflationUp1pp,
    apply: (b) => simulateFireState(
      baseline: b,
      inflationRate: b.plan.inflationRate + 0.01,
    ),
  ),
  _Preset(
    label: l10n.fireOsSimulationsPresetSwrTight,
    apply: (b) => simulateFireState(baseline: b, safeWithdrawalRate: 0.035),
  ),
  _Preset(
    label: l10n.fireOsSimulationsPresetCashBucketUp24,
    apply: (b) => simulateFireState(baseline: b, targetCashBucketMonths: 24),
  ),
];
