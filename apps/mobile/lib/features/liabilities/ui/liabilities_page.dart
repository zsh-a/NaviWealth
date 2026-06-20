import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/liability.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/liability_summary.dart';
import 'liability_l10n.dart';

/// List of all of the user's liabilities. Tapping a row drills into the
/// detail / amortization screen. The FAB opens the create form.
class LiabilitiesPage extends ConsumerWidget {
  const LiabilitiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final asyncList = ref.watch(liabilitiesStreamProvider);
    final summariesAsync = ref.watch(allLiabilitySummariesProvider);
    final summaries = summariesAsync.value ?? const {};

    final body = asyncList.whenOrError(
      data: (items) {
        if (items.isEmpty) {
          return _LiabilitiesEmptyState(l10n: l10n);
        }
        // Standard two-line ListTile height — lets the scroll view skip
        // per-item layout during scroll, critical for 120fps.
        const itemHeight = 72.0 + 8;
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.s16).copyWith(
            bottom:
                const EdgeInsets.all(AppSpacing.s16).bottom +
                64 +
                MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: items.length,
          itemExtent: itemHeight,
          itemBuilder: (context, i) => _LiabilityListTile(
            liability: items[i],
            summary: summaries[items[i].id],
            formatters: formatters,
          ),
        );
      },
      error: (error, _) => AppEmptyState.error(
        title: l10n.commonLoadFailed,
        message: '$error',
        action: FButton(
          variant: FButtonVariant.ghost,
          onPress: () {
            ref.invalidate(liabilitiesStreamProvider);
            ref.invalidate(allLiabilitySummariesProvider);
          },
          child: Text(l10n.commonRetry),
        ),
      ),
    );

    return AppPageScaffold(
      title: l10n.liabilitiesAppBarTitle,
      childPad: false,
      child: body,
    );
  }
}

class _LiabilitiesEmptyState extends StatelessWidget {
  const _LiabilitiesEmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: FLucideIcons.landmark,
      title: l10n.liabilitiesEmptyHint,
    );
  }
}

class _LiabilityListTile extends StatelessWidget {
  const _LiabilityListTile({
    required this.liability,
    required this.summary,
    required this.formatters,
  });

  final Liability liability;
  final LiabilitySummary? summary;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final remaining = summary?.remainingPrincipal;

    return SoftCard(
      child: FTile(
        title: Text(liability.name),
        prefix: CircleAvatar(
          backgroundColor: AccentColors.tint(context.theme.colors.brightness),
          child: Icon(
            _iconFor(liability.type),
            color: context.theme.colors.primary,
          ),
        ),
        subtitle: Text(
          '${liabilityTypeLabel(l10n, liability.type)} · '
          '${formatters.percent(liability.interestRate.toDouble())}',
        ),
        suffix: remaining != null
            ? Text(
                formatters.currency(remaining, code: liability.currency),
                style: context.theme.typography.md,
              )
            : Text(
                formatters.currency(
                  liability.principal,
                  code: liability.currency,
                ),
                style: context.theme.typography.md,
              ),
        onPress: () => context.push(AppRoutes.wealthLiability(liability.id)),
      ),
    );
  }

  IconData _iconFor(LiabilityType t) => switch (t) {
    LiabilityType.mortgage => FLucideIcons.house,
    LiabilityType.carLoan => FLucideIcons.car,
    LiabilityType.creditCard => FLucideIcons.creditCard,
    LiabilityType.consumerLoan => FLucideIcons.banknote,
    LiabilityType.studentLoan => FLucideIcons.graduationCap,
    LiabilityType.marginLoan => FLucideIcons.chartLine,
    LiabilityType.other => FLucideIcons.landmark,
  };
}
