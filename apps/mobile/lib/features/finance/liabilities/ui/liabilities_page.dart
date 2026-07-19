import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/format/providers.dart';
import '../../../../core/shell/shell_chrome.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
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
      context: context,
      data: (items) {
        if (items.isEmpty) {
          return _LiabilitiesEmptyState(l10n: l10n);
        }
        return ListView(
          padding: shellTabContentPadding(context),
          children: [
            AppGroupedSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _LiabilityListTile(
                      liability: items[i],
                      summary: summaries[items[i].id],
                      formatters: formatters,
                    ),
                    if (i < items.length - 1)
                      const AppGroupedDivider(indent: AppSpacing.s48),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      error: (error, _) => AppEmptyState.error(
        title: l10n.commonLoadFailed,
        message: userSafeErrorMessage(context, error),
        retryLabel: l10n.commonRetry,
        onRetry: () {
          ref.invalidate(liabilitiesStreamProvider);
          ref.invalidate(allLiabilitySummariesProvider);
        },
      ),
    );

    return AppPageScaffold(
      title: l10n.liabilitiesAppBarTitle,
      actions: [
        AppHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.liabilitiesAddAction,
          onPress: () => context.push(FinanceRoutes.wealthLiabilityNew),
        ),
      ],
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
      action: FButton(
        variant: FButtonVariant.primary,
        onPress: () => context.push(FinanceRoutes.wealthLiabilityNew),
        prefix: const Icon(FLucideIcons.plus),
        child: Text(l10n.liabilitiesAddAction),
      ),
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

    return FTile(
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
              style: context.theme.typography.body.md,
            )
          : Text(
              formatters.currency(
                liability.principal,
                code: liability.currency,
              ),
              style: context.theme.typography.body.md,
            ),
      onPress: () => context.push(FinanceRoutes.wealthLiability(liability.id)),
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
