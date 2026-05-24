import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/wheel_lifecycle.dart';

/// `/plan/wheel` — per-underlying Wheel cycle review
/// (`docs/roadmap-next.md` §3.3).
///
/// Reads [wheelLifecyclesProvider] which derives cycles from the
/// existing trade journal stream — no new sync table, no extra IO.
/// Each underlying renders as one tile showing the current stage,
/// cumulative income, and whether a position is open.
class WheelLifecyclePage extends ConsumerWidget {
  const WheelLifecyclePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cyclesAsync = ref.watch(wheelLifecyclesProvider);

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.planWheelTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: cyclesAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (_, _) => Center(
          child: AppEmptyState(
            icon: Icons.autorenew_outlined,
            title: l10n.planWheelEmptyTitle,
          ),
        ),
        data: (cycles) {
          if (cycles.isEmpty) {
            return Center(
              child: AppEmptyState(
                icon: Icons.autorenew_outlined,
                title: l10n.planWheelEmptyTitle,
                message: l10n.planWheelEmptyBody,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s12,
              AppSpacing.s16,
              AppSpacing.s24,
            ),
            itemCount: cycles.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
            itemBuilder: (context, i) => _WheelTile(cycle: cycles[i]),
          );
        },
      ),
    );
  }
}

class _WheelTile extends StatelessWidget {
  const _WheelTile({required this.cycle});

  final WheelLifecycle cycle;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final stageLabel = _stageLabel(cycle.stage);
    return FCard.raw(
      child: FTile(
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            _stageIcon(cycle.stage),
            size: 18,
            color: colors.mutedForeground,
          ),
        ),
        title: Text(cycle.symbol),
        subtitle: Text(stageLabel),
        suffix: MoneyText(
          amount: cycle.cumulativeIncome.toDouble(),
          currencyCode: cycle.currency,
          showSign: true,
        ),
      ),
    );
  }
}

IconData _stageIcon(WheelStage stage) => switch (stage) {
  WheelStage.between => Icons.circle_outlined,
  WheelStage.cashWaiting => Icons.account_balance_wallet_outlined,
  WheelStage.shortPut => Icons.south_west_outlined,
  WheelStage.putExpired => Icons.check_circle_outline,
  WheelStage.putAssigned => Icons.input_outlined,
  WheelStage.sharesHeld => Icons.inventory_2_outlined,
  WheelStage.shortCall => Icons.north_east_outlined,
  WheelStage.callExpired => Icons.check_circle_outline,
  WheelStage.callCalled => Icons.output_outlined,
};

/// Labels are pinned in code (not l10n) because the Wheel stages are a
/// canonical strategy taxonomy — translating "short put" into a free
/// rendering for each locale would lose the strategy semantics.
String _stageLabel(WheelStage stage) => switch (stage) {
  WheelStage.between => 'Between cycles',
  WheelStage.cashWaiting => 'Cash waiting',
  WheelStage.shortPut => 'Short put (open)',
  WheelStage.putExpired => 'Put expired',
  WheelStage.putAssigned => 'Put assigned',
  WheelStage.sharesHeld => 'Shares held',
  WheelStage.shortCall => 'Short call (open)',
  WheelStage.callExpired => 'Call expired',
  WheelStage.callCalled => 'Called away',
};
