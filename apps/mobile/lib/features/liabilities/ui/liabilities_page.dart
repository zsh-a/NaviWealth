import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/providers.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/liability.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
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
    final asyncList = ref.watch(liabilitiesStreamProvider);

    final body = asyncList.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (items) {
        if (items.isEmpty) {
          return _LiabilitiesEmptyState(l10n: l10n);
        }
        return ListView.separated(
          padding: Spacing.pageMobile,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.s8),
          itemBuilder: (context, i) =>
              _LiabilityListTile(liability: items[i]),
        );
      },
    );

    if (embedded) return body;

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.liabilitiesAppBarTitle),
        actions: const [],
      ),
      body: body,
    );
  }
}

class _LiabilitiesEmptyState extends StatelessWidget {
  const _LiabilitiesEmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: Spacing.s16),
            Text(
              l10n.liabilitiesEmptyHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiabilityListTile extends ConsumerWidget {
  const _LiabilityListTile({required this.liability});

  final Liability liability;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final summary = ref.watch(liabilitySummaryProvider(liability.id));
    final remaining = summary.maybeWhen(
      data: (s) => s?.remainingPrincipal,
      orElse: () => null,
    );

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.s16,
          vertical: Spacing.s8,
        ),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            _iconFor(liability.type),
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(liability.name),
        subtitle: Text(
          '${liabilityTypeLabel(l10n, liability.type)} · '
          '${formatters.percent(liability.interestRate.toDouble())}',
        ),
        trailing: remaining != null
            ? Text(
                formatters.currency(remaining, code: liability.currency),
                style: theme.textTheme.titleMedium,
              )
            : Text(
                formatters.currency(
                  liability.principal,
                  code: liability.currency,
                ),
                style: theme.textTheme.titleMedium,
              ),
        onTap: () =>
            context.push('/portfolio/liabilities/${liability.id}'),
      ),
    );
  }

  IconData _iconFor(LiabilityType t) => switch (t) {
    LiabilityType.mortgage => Icons.home_outlined,
    LiabilityType.carLoan => Icons.directions_car_outlined,
    LiabilityType.creditCard => Icons.credit_card_outlined,
    LiabilityType.consumerLoan => Icons.payments_outlined,
    LiabilityType.studentLoan => Icons.school_outlined,
    LiabilityType.marginLoan => Icons.show_chart_outlined,
    LiabilityType.other => Icons.account_balance_outlined,
  };
}
