import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'data/dashboard_providers.dart';
import 'domain/dashboard_models.dart';
import 'ui/allocation_card.dart';
import 'ui/currency_mismatch_banner.dart';
import 'ui/trend_card.dart';

/// Dashboard surface (FIR-52).
///
/// Two cards: a category-allocation pie + drill-down list, and a net-worth
/// trend chart with time-range chips. Layout adapts at the
/// [Breakpoints.mobile] boundary — single column on phones, two-column on
/// tablet / desktop so the cards sit side-by-side.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeAppBarTitle),
        actions: [
          IconButton(
            tooltip: 'AI 助手',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.push('/ai'),
          ),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => _ErrorBody(error: e),
        data: (snapshot) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CurrencyMismatchBanner(),
            Expanded(child: _DashboardBody(snapshot: snapshot)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/assets/trade'),
        tooltip: '录入交易',
        child: const Icon(Icons.add_chart),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = !Breakpoints.isMobile(width);
        final padding =
            isWide ? Spacing.pageWide : Spacing.pageMobile;
        final header = _NetWorthHeader(snapshot: snapshot);
        final allocation = AllocationCard(snapshot: snapshot);
        final trend = TrendCard(snapshot: snapshot);

        if (isWide) {
          return ListView(
            padding: padding,
            children: [
              header,
              const SizedBox(height: Spacing.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: allocation),
                  const SizedBox(width: Spacing.s16),
                  Expanded(child: trend),
                ],
              ),
            ],
          );
        }
        return ListView(
          padding: padding,
          children: [
            header,
            const SizedBox(height: Spacing.s12),
            allocation,
            const SizedBox(height: Spacing.s12),
            trend,
          ],
        );
      },
    );
  }
}

class _NetWorthHeader extends StatelessWidget {
  const _NetWorthHeader({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hasData = !snapshot.isEmpty;
    final value = hasData ? snapshot.netWorth.amount.toDouble() : null;
    return Card(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeNetWorthTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.s8),
            MoneyText(
              amount: value,
              currencyCode: snapshot.baseCurrency,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
              showSign: value != null && value < 0,
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              hasData
                  ? l10n.dashboardNetWorthBreakdown(
                      _formatBaseAmount(snapshot.totalAssets.amount.toDouble()),
                      _formatBaseAmount(
                        snapshot.totalLiabilities.amount.toDouble(),
                      ),
                      snapshot.baseCurrency,
                    )
                  : l10n.homeNetWorthSubtitle(snapshot.baseCurrency),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBaseAmount(double v) => v.toStringAsFixed(0);
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Text(
          AppLocalizations.of(context).dashboardSnapshotError('$error'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}
