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
  const LiabilitiesPage({super.key, this.embedded = false});

  /// When true, renders without Scaffold/AppBar/FAB — for embedding
  /// inside [PortfolioPage].
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final asyncList = ref.watch(liabilitiesStreamProvider);
    final summariesAsync = ref.watch(allLiabilitySummariesProvider);
    final summaries = summariesAsync.value ?? const {};

    final body = asyncList.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => Center(child: Text('$e')),
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
    );

    if (embedded) return body;

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.liabilitiesAppBarTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: Material(color: Colors.transparent, child: body),
    );
  }
}

class _LiabilitiesEmptyState extends StatelessWidget {
  const _LiabilitiesEmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FLucideIcons.landmark,
              size: 48,
              color: context.theme.colors.mutedForeground,
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.liabilitiesEmptyHint,
              textAlign: TextAlign.center,
              style: context.theme.typography.sm.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ],
        ),
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final remaining = summary?.remainingPrincipal;

    return SoftCard(
      child: FTile(
        title: Text(liability.name),
        prefix: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            _iconFor(liability.type),
            color: theme.colorScheme.onPrimaryContainer,
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
